# Desk Pets - design

Living document. Decisions are marked **Decided**, ideas still being weighed are marked **Open**.

## Pitch

An idle collecting game that lives on your desktop. Pull loot boxes, collect pets built from
random parts in rare variations, and chase an extremely rare pet over months. One pet walks on
your windows while you work; behind it, a swarm of thousands goes out on adventures to fund your
next pulls. Not all of them come back.

Paid game on Steam. All loot boxes and gambling use in-game currency only; nothing is ever sold
for real money.

## Pillars

1. **Collect (the heart).** Opening boxes has to feel like opening trading card packs: the
   reveal, the glow, the rare pull. The collection book and its variations are the long chase.
   (Inspiration: TCG Card Shop Simulator - foils, ghost foils, the urge to open one more.)
2. **Care (active, one pet).** The pet on your desktop, and hands-on activities for when you
   focus on the game.
3. **Adventures (idle, the swarm).** No thinking needed, time-gated, scales from one pet to
   hundreds of thousands. Produces the loot that feeds the other two pillars.

Visually non-intrusive: the game is a small pinned home panel plus a pet that can walk on top of
your windows. It hides when something is fullscreen.

## Theme

**Decided.** On the outside, a cute pastel collect-a-desktop-pet game. In reality, you're sending
troops off to be killed. The game itself never lets on.

- **Never graphic.** No blood or gore, nothing shown. Target around PEGI 12 (the simulated
  gambling likely sets that floor anyway).
- **The game never winks.** Everything looks and sounds cute and upbeat, at every depth. The
  darkness comes only from what the player chooses to do and what they infer; no text, sound or
  UI ever acknowledges or hints that anything is dark. **Decided**
- **Progress drives it.** Early game is small, safe foraging trips. Later the player unlocks
  deadlier adventures and swarm automation, and chooses to use them; the cheerful tone stays
  exactly the same, which is the point.
- **The arc:** early on you open cute pets. Late game you send hundreds into a dungeon to find
  the one part that makes your favourite cat perfect.
- **Plushie logic** (**Open**): parts are sewn on with stitches and button eyes, so grafting reads
  as crafting.
- **The narrator is innocent:** the active pet comments on results and sincerely never
  understands ("Only 12 came back! They must have found somewhere nicer!"). See Adventures.
- **The night sky** (**Decided**, inspired by Noita's star per death): every pet that doesn't come
  back adds one tiny, dim star to the background of the home panel, in a spot taken from its
  number (star i, so pets from the herd count too) and a colour taken from that pet. Never explained, never counted, really hard to notice. Early on there are a
  handful of specks; late game the panel is a dark starry sky, so the mood darkens by itself as
  a direct result of what you've done. Past what a small panel can hold, new stars thicken a
  faint milky band instead of adding specks.

## Core loop

```
 open boxes ──> new pets, parts, gear ──> collection book
      ^                                        │
      │                                        v
   coins, boxes <── adventures  <── gear up, craft, risk your best pets
```

- **Active play advances faster than idling** (target roughly 3-5x). Checking in is always
  rewarded, never required. **Decided**
- **Pets are only lost by choice** - by sending them on an adventure or betting them on a risk
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
- **Stats** - e.g. power, luck, speed, used on adventures. Rolled in a range set by rarity.

Rarity tiers: common, uncommon, rare, epic, legendary, mythic. A pet's overall rarity comes from
its parts and finish together.

**Open:** how many parts per slot at launch; whether trait count grows with rarity.

## Loot boxes

- Bought with coins, found on adventures, given as check-in rewards. Never sold for money.
  **Decided**
- **Priced in capsules** (built): a box's price is a number of the machine's plain capsules
  (boxes.json "capsules", starter 50; the room's "more room" too) times what a capsule is worth now (Machine.coin_value), shown
  in coins. So 50 coins on a fresh machine, and the shop keeps up with the machine all game instead
  of getting 2500x cheaper (GameState.box_price / box_cost). One box's price is rounded first, so
  10 boxes always cost 10x the chip. What your pet keeps when it buys boxes itself ("keep at
  least") is in the same capsules (boxes.json "reserve": starts at 50, -/+ step 50, slider top
  2000), shown in coins, so it keeps meaning something as prices grow.
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

**Sound of one opening:** the tear follows your hand. When the strip comes off the pack breathes
out (a soft airy shimmer) and a hum starts inside it; each rarity step adds a musical layer on top
(celesta, strings, choir and harp, brass and glockenspiel, and for mythic a bell that's slightly
wrong) with a rising harp chime; pulling the pet out brings tremolo strings that want to resolve,
and the reveal plays the rarity's fanfare (a music-box ta-da for common up to the whole orchestra;
mythic detours through D flat before it comes home). All cheerful, all in F like the room music,
which steps back while you open. Made in LMMS by tools/music/pack_sounds.py.

## Collection book

- Tracks every part discovered, and every finish seen for each body.
- Shows how many of each you've pulled, with undiscovered entries as silhouettes.
- Owned pets: the **bookcase** (C1, look A, built): a pink cushion on top with your active pet,
  favourites and the best ones (holo and better, a part new to the book), then a plank per rarity
  you have: a tilted tag ("common 48,210"), the newest 4 standing, a mound of tiny pets that grows
  with the count (about log10, at most 60) and the shiny count. Tap a plank (or a cushion pet) to
  open the shelf: the herd as chips (plain and shiny counts), the always-cards, a stitched line, the
  newest ones, and the chosen pet's sticker with the heart (favourite) and make active.
- **The herd** (C3's base, built): plain pets (below holo) fold into a **count per rarity x
  finish**, so millions fit in the save and on screen. Always a card: favourites, the active pet,
  holo or better, a pet that brought a part new to the book, pets with buttons (F2, later), and
  pets something needs whole (away on an adventure, a good pull you haven't seen, leading a party);
  each shelf also keeps its newest 20 plain pets as cards. Errands, workers and parties draw from
  the counts; an adventure takes **stand-ins** (a pet from a count, its rarity's average stats, no
  traits, a look from a seed) that come home into the count or leave it (a star).
- **The room** (built, simple first version): one cap for every plain pet together (500 at first,
  x1.5 per upgrade, bought with coins; placeholders in data/herd.json). "More room" is priced in
  capsules like boxes and errand tools (herd.json room "capsules" 500 x1.8 per level, x what a
  capsule is worth now): 10 starter boxes a level, all game, and the open card follows the machine. A pill on the pets tab
  shows it once the first pet folds; full, it turns pink and wiggles, box openings wait on the pile
  (by hand, your pet, box workers, the machine's pet box: nothing is lost) and your pet squishes.
  Gifts (the tutorial's pets, the basket's pet) always come in.
- **New homes** (C3 look A, built): the first time the room is full a striped stall turns up in a
  side column beside the bookcase (no popup; your pet mentions it). Tap a plank to pick that shelf
  (dashed pink border), tap it again to open it; the stall takes 1 / 10 / 100 / all of the shelf's
  plain pets (normal before shiny, resting before working, counts before the oldest cards; never
  favourites, the active pet, new parts, holo and better, pets away). Points per rarity (common 1,
  uncommon 2, rare 5, epic 12, legendary 20, mythic 40; data/new_homes.json) fill a box jar, 25 = a
  starter box on your pile (the sunny box once B1 is in). Every take your pet says "they'll have a
  big garden!", always those words. An opened shelf takes the whole width (the stall steps aside).
- **The sorting rule** (built): after 300 pets sent by hand a tilted index card turns up under the
  stall: off | on, "new pets below ‹rare› go to ‹new homes / work›", keeps "✦ ‹holo› and up" (a
  finish stepper), new parts and favourites (always). Off by default; only pets out of boxes (yours,
  your pet's, the box tables', the machine's pet box) that arrive after it's on are sorted: new homes
  = they leave at once (points, stars; the reveal still shows them), work = they start where "new
  pets join here" is on, or on every open errand. "sorted today N" on the card and on each plank
  under the line (local day).
- **Stars:** every pet that leaves (new homes, lost on an adventure) adds a night-sky star, never
  explained.
- **Open:** completion rewards (per page, per body, per finish set).

## Care (active side)

- The desktop pet: walks on your windows, reacts to pats, can be parked at home.
- Needs (hunger, mood) are opportunities, not threats: caring gives temporary buffs
  (e.g. well fed = +50% coins for 2 hours).
- Activities for when you're focused on the game: junkyard digging for parts, trading with NPCs,
  crafting. **Open:** exact list and order.
- Desktop events while the pet is out: finding coins on window edges, catching falling things,
  rare visitors.
- **Rummaging** (built): something to do while the first adventures are out. The room on the home
  tab has spots (little dresser, plant pot, sock pile, toy box, data/rummage.json) that twinkle
  when something's in them. Tap one and your pet hurries over, dives in head first and comes out
  with coins (2-4), sometimes an xp, and (once parts are open) now and then a common part. Each spot refills after 2 min
  (also while the game is closed, holding one find at most). Tap several and it does them in
  turn. Opens after the tutorial. At most about 6 coins a minute, about half a garden trip
  (tools/balance.gd); later the coin hunt errand is the automated version of this.
- **The capsule machine** (built, the machine tab, data/machine.json): the always-there active
  thing. Grab the pink knob and pull the lever towards you: it clicks past its notches, clunks at
  the bottom, the machine jolts, the capsules in the glass jump, and ONE capsule drops out of the
  flap, bounces, wobbles and splits open: one pull, one prize. **One pull at a time** (Emilia): the
  lever won't budge until the capsule has opened (1.4 s, the springier spring makes it quicker), so
  it's fewer, better pulls and kinder to your wrist; a capsule starts at 1 coin (mostly a few coins that fly up to the counter;
  sometimes an xp, a part, a whole box or a golden capsule). Every pull lights one of the lucky
  lights; all lit = a shiny capsule (only good prizes) and FEVER (10 s where every capsule pays
  double, the room music steps back for a bouncy fever tune). The upgrade shelf (Cookie Clicker's
  store): fuller capsules, a springier spring, shinier capsules, luckier lights, and locked ones
  found on adventures later. **Decided (Emilia):** it is NEVER automated. Pets don't work it (they
  earn on errands); it stays relevant all game as a side objective you keep building, so the game
  is never fully automated and sitting there pulling is always best. Its point: coins to get pets.
  **Capsule toys (built, data/toys.json, Toys):** the machine's own chase. About 1 capsule in 15
  holds a pixel-art toy from a SET (the first: backyard friends, 4 common, 2 uncommon, 1 rare,
  1 secret "???"), in a finish (normal, holo, gold foil, ghost). A good prize pops up as a PICTURE.
  Toys live in the collectibles tab (was pets: pets | toys | book). A toy only boosts while your
  pet PLAYS with it: pick a quick play (10 min), a long one (30 min) or all afternoon (2 h); it
  holds the toy on its moon and won't let go ("do not disturb me!"); one play slot, +1 for a
  finished set. Boosts are multipliers, small early (a common toy x1.1) and big later (levels,
  finishes: holo x1.25, gold foil x1.5, ghost x2 of the extra): coins, luck (the machine and
  adventures), xp, faster capsules, longer fever, more toys, more adventure loot, or everything
  (the moth). Playing WEARS a toy (its boost shrinks, never below half); nothing is ever lost.
  The WORKBENCH (was the bag: your pet | toys) combines spares into levels (always works), fixes
  wear for coins, and SACRIFICES 3 spares for a chance at a special finish (odds shown, gone
  either way). Max level = a FAVOURITE: always on, never wears (the late-game permanent buffs).
  Rerolling toys was cut (too strong). Mockups: toys.html, upgrading.html, toy-designs.html (B).
  **The broken machine and its tree (Emilia, built):** the machine is an old broken one you fix
  up (machine tab: machine | upgrades). The upgrade TREE (data/machine_tree.json) has a trunk of
  repairs (tape up the crack, oil the lever, unstick the flap, new glass, rewire the lights, better
  drops) with branches growing off them: coin multipliers, more chutes, double/triple drops, shiny
  balls (x2, x3, x4), longer fever. Repairs cost coins and BITS (gear, spring, bolt, glass) that
  pets bring home from backyard adventures, each place its own kind, so machine and adventures
  both matter and neither idles yet. The map says which: each place has its bit and
  "bolts here!" under its name, its card says "brings home bolts", and the ? cloud of a place
  nobody's found yet says "bolts out this way?" while the machine still needs that bit (MapView.bit_of). Everything fixed shows on the machine. After "new glass" a
  capsule holds a scrap of a map (intel): the page beyond the fence opens. From the start (after
  the tutorial) a pull's first capsule now and then (about 1 pull in 400) holds a **box with a pet inside**, ripped
  open right at the machine with the real ritual; you can't buy or open boxes yet (the boxes tab
  waits for better drops), so this is the only way to more pets early. With no pets besides your
  active one, a pet box is sure within 10 pulls (machine.json "pet_box"): losing your pets on
  adventures can never leave you stuck. Better drops puts boxes
  and toys in the machine (and opens those). Parts come much later (a "woah" moment once you know
  how pets roll). Coins go huge (1.2k, 3.4M, 5.6B) and prices keep up (tools/machine_pace.gd).
  Lore: you're conquering the backyard, then beyond; the voice never says so.
  **The start (Emilia, built, older):** a new game shows only home, the machine and collectibles (toys
  locked "???"). Pull the lever; on the 3rd pull your first pet comes out OF THE MACHINE and is your
  active pet. Then it's you and the machine for a while: it starts bad (1 coin a capsule, slow) and
  upgrades are quick at first, then expensive and marginal (tools/machine_pace.gd: 19 upgrades is
  about 20 min of steady pulling). At 19 upgrades (data/tutorial.json) a second pet comes out
  holding a map: adventures open and you send it. After that new things come through adventures,
  spaced out: boxes after 4 trips, toys after 10 (data/unlocks.json "trips"), plus the finds as
  before. The machine only gives what's open (no boxes before the boxes tab, no toys before toys).
  Settings' dev part shows when each thing opened, in minutes, for pacing tests.
  Mockup: design/mockups/screens/capsules.html. **Next:** rummaging changes to finding machine bits;
  pull value grows with the rest of your income; new globes per map page; rewards get tuned.

## Adventures (idle side)

**Decided.** Adventures are everything pets are sent out to do, and the main source of the
economy: currency, body parts, and rewards for mechanics not designed yet. Rewards are generic
(`{ kind, ... }` in the data, one handler per kind), so new ones are easy to add.

- **Types unlock over time.** The game starts with a plain UI and one type, **foraging**. Later:
  dungeons, scavenging, trading trips, exploration. Types differ on risk (safe and steady up to
  deadly and lucrative), yield (which part of the economy they feed), duration (quick errands up
  to long trips that run while the game is closed) and involvement. New types are data.
- **Locations** belong to a type; each is a chain of events with options and outcomes (losses,
  injuries, loot, progress). Groups use aggregate maths (the party's total stat against the
  difficulty), so the same events work for 1 pet or thousands, and a trip that finished while the
  game was closed is caught up in one calculation.
- **Involvement scales with the party:**
  - 1 pet: the player makes every choice.
  - Small parties: events pop up as choices, with a default if ignored (after a minute).
  - Swarms: standing policies ("always fight", "leave the wounded behind") and the trip resolves
    on its own. Swarms and policies come with a later **automation** unlock.
- **Party size grows through finds** (**Decided**, for the first ~2 hours of play): one pet at
  first; the cart (woods) allows 3, the wheelbarrow (orchard) 5, the hay wagon (meadow, only
  after the wheelbarrow) 10. Each find gets an unlock popup. Finds are never a choice: the pet
  says "i found a basket!" and brings it home (the cart can stay stuck in the mud for a later trip,
  the hay wagon only turns up for 3+ pets). Why bring more pets is said in plain
  words on the place card: more friends bring home more and tricky bits get easier, but more
  friends can get hurt. (Coins grow with each pet, finds with the square root of the party.)
- **The trail** (**Decided**): one pet or a small party can be watched walking the path. Things to
  grab turn up (coins, xp, a healing leaf, now and then a part). No click-spamming: "toss a
  treat" makes the pets zoom (3x speed for 8 s), then it takes 15 s to be ready again (the treat
  pouch, see Gear, makes both better).
- **Discovery:** pets spot neighbouring places on the way home; exploration trips (the far
  fields) bring back rumours, word of places further off (the orchard, the well and below). A
  rumour shows on the map; tapping it and saying yes opens the place. The pet explains this the
  first time. No NPCs or towns.
- **Narration:** the only voice in the game is the active pet. When the adventures tab opens it
  comments on rumours and recent results in short cheerful lines, sincerely innocent. Its parts
  shape its personality (nervous, overconfident, dim), so the same rumour sounds different
  depending on the pet.
- **Body parts are the late-game chase:** a rare part found far away gets grafted onto your
  favourite pet (see Theme). Mass pets are sacrificable scaling; the real chase is a couple of
  extremely good pets built up over a long time.
- Scale: 1 pet → a few with gear → 10 → hundreds → 100k+.
- **Open:** raids (all pets as one force against a boss) as a later type.

## Errands (idle side, safe)

**Decided.** The safe, steady floor under adventures: resting pets are put on jobs in the
errands tab (a corkboard of sticky notes), opened by the little basket found in the meadow. The
basket only turns up once "unstick the flap" is fixed (event field `after_machine`), so errands open
when bits start holding the machine up, not in the first minutes.
Nobody is ever lost on an errand, and errands never bring rare parts or new places.

- **One rule for every job** (`data/errands.json`, `scripts/idle/jobs.gd`): a meter fills once
  every `seconds` with one pet, crew^0.8 times as fast with a bigger crew (each extra pet helps a
  bit less, so spreading beats stacking), and pays each time it's full. A pet's stat for the job
  and its traits nudge its speed (about ±25%; rarer pets have higher stats).
- **Errands are the idle coin maker and the coin sink** (Emilia, 2026-09-28: coins piled up while
  bits held the machine back, so pulling felt pointless). Your lever isn't automated in the early
  stages (later your pet cranks a slow machine of its own, see Automation); errands are. Pay is in **capsules**: a find is worth N of the machine's plain capsules
  (`Machine.coin_value`), so every machine upgrade raises errands too and idle coins keep up all
  game while staying well under pulling (one pet on the coin hunt ≈ 2.5 capsules a minute; pulling
  is 25+).
- **The basket has a pet asleep in it** (`pet_job` on the unlock): a new player only has two pets
  then (the active one and the adventurer), so this one starts on the coin hunt.
- **Jobs:** coin hunt (coins), the lemonade stand (tips: pays by the crew's rarity, so a rare pet
  pays off early; opens at coin hunt lv 10) and the scrapyard (common parts; an uncommon now and
  then with 5+ pets). A job with `needs` is not there until that unlock opens: the scrapyard waits
  for parts (a late feature). Nothing hands out parts before then (GameState.grant drops them); a
  v19 save closes parts again under 40 trips.
- **Upgrades page: the pegboard** (`ErrandToolsView`, mockup errands-upgrades.html look A). Coins
  buy tools, each with levels that cost more every time (some never end): a job's own (coin hunt:
  sniffier noses +1 capsule a find, quicker paws, deeper pockets = big finds; lemonade: sweeter
  lemons, a bigger sign, fancy cups = rare pets tip double) and ones for everyone (snack break,
  comfy naps = longer full speed while away, shiny pebbles = shiny finds once the machine has
  shiny balls, teamwork = better crew power). Buy x1 / x10 / max. The top of the tab always shows
  "◆ N a minute on errands", and the card shows before → after, so every buy is visible progress.
  Tools are priced in capsules like errands pay (errands.json tool "capsules" x Machine.coin_value,
  x "grow" per level): set so a capsule worth 75 coins (about when the basket opens) gives the old
  coin prices, and they keep up with the pay as the machine grows (Jobs.tool_base / tool_cost).
- **Job levels and goals:** a job's level is its tools' levels added up; gold stars along a dotted
  track mark its goals (coin hunt: lv 10 the lemonade stand, lv 25 and 50 x2 coins, lv 100 x3). An
  unlock can wait for a level (`earn.job_level`).
- **The player assigns pets** (tap a resting pet then a job, or + / −). **Busy paws** (C3): each
  errand and each workers' job (machines, box tables; not adventures) has a "new pets join here"
  switch, off by default (errands: in the shoebox under "new pets join", one per errand; workers:
  on the job's side card). New pets (boxes, gifts, pets home from adventures, your old active pet)
  fill switched-on machines with room first (the best workers), the rest spread over switched-on
  errands (smallest crew first); nothing on: they rest. "Share them out" stays. Going on an
  adventure takes a pet off its job.
- **Scales from a couple of pets to thousands:** up to 6 on a job each get a polaroid; past that
  a pile, the count and a little crowd, and + / − move 1, 10, 100 or all.
- **Offline:** full speed for 8 h, then half, up to the 12 h cap; the tab notes what came in.
- **More jobs (A3, built 2026-09-28, plan docs/plans/A3.md)**, each opened by a goal on another
  job's level (lemonade lv 10 → the savings jar, coin hunt lv 25 → the kitchen, savings jar lv 10 →
  scouting). Only the job that is an open job's NEXT goal shows as a waiting note / waiting shelf,
  so there's never a row of locked notes.
  - **Savings jar:** fills slowly (30 min with one pet) and pays one big lump (100 capsules' worth),
    with its own crew power 0.5: one pet there beats one on the coin hunt, a crew doesn't. The note
    says "7.4k coins when full" and "full in 24m 10s"; a full jar pops a big gold number and a coin
    burst, never the stream. Tools: a bigger jar, a wider slot.
  - **Kitchen:** brings nothing, every other job works faster: 0.3 x cooks / (cooks + 2) (1 cook
    +10%, 2 +15%, 4 +20%, 10 +25%, never past 30%), capped at what those cooks would add on a real
    job ((1 + cooks / others)^crew_power − 1), so it never beats one. Each full meter is a meal for
    your pet (+10 food, +2 mood), but only up to 70 (`meal_upto`, `Jobs.feed`): the kitchen keeps
    it from going hungry, filling it up is still yours to do. No tools, no level.
  - **Scouting:** each full meter is a scout note (hold 2, a map case holds more; a full hold stops
    the meter). A trip you send yourself to a place with something left to spot or hear takes one:
    +0.15 on each lead's spot chance and rumours x1.5 (the note's numbers ride along on
    `RunState.scout`, from `Jobs.scout_note`; the scouting job is whichever has a `scout` block,
    `Jobs.scout_job`; `Intel.roll` bonus, `AdventureRunner.scouted`). Never auto parties, never dungeons (`"scout": false` on the type).
    Chance only: the map's ? clouds stay a surprise; no odds shown. The away card gets a tiny note
    doodle. Tools: a map case, field glasses.
  - Share out and your pet's sharing skip the kitchen and scouting (`"share": false`).
- **Later jobs** (ideas, **Open**): recycling, digging, show-off, training, mapmaking,
  stargazing, a lab; the dark twist shows only in what jobs describe.

## Automation (idle side, your pet)

**Decided (Emilia, 2026-09-28), first layer built.** The automation tab: your active pet does ONE
job at a time for you; moving it stops the job it left (the game never explains this, the pet just
says what it stopped). Later layers hand whole stages off to pets (workers, packs, pets per second);
see the memory note on the automation tab for the plan.

- **Opens** when the machine is fully fixed ("better drops"): a pet brings home a tiny, broken,
  pet-sized capsule machine from the far fields (event `fields_tiny_machine`, `after_machine`
  drops), and your pet fixes it by itself ("i watched you fix every single gear"). Hidden until then.
- **Jobs are taught with coins** (`data/automation.json`, `scripts/idle/automation.gd`), and a job
  that isn't there yet is fully hidden:
  - **crank a machine** (with the tab): your pet cranks its own little machine, a pull every 48 s
    at first (you pull about 2 a second), each a plain capsule worth what yours are (coins, toys, a
    box now and then), no lucky lights, fever or pet boxes. Tools: a smoother crank (faster), a comfy
    stool (keeps cranking while the game is closed, an hour a level; without it the machine stops).
  - **run adventures** (after 60 trips once the machine job is taught, `feature:auto_adventures`):
    pick a place (‹ ›) and how many pets (− +); the party is welcomed back quietly when it's home and
    sent out again, events take their usual pick.
  - **open boxes** (the cushion, which now waits for the tab too): your pet opens your pile, but
    only while it's on this job. It can't buy boxes until the piggy bank.
- **Look:** a card per job (mockup automation.html look C), your pet sits in the card of the job
  it's doing, the side card teaches it, moves it or takes it off, and holds the tools.
- **Workers (built):** "teach the others" turns up in a job's upgrades once your pet's tools are far
  enough (the machine: crank lv 3); buying it opens a second page, **your pet | workers** (hidden
  until then). Workers need a spot each, bought with coins (machines, box tables, adventure
  parties; each costs more), and you put resting pets on them yourself (+ / − / fill up, best
  pets first). Pets can't buy spots or boxes (on purpose: you restock). A worker is slower than
  your pet: a common half speed, +0.1 a rarity step (a mythic keeps up), so good pets are worth
  putting to work. Machine workers pull capsules, box workers open your pile (not the boxes you
  save), each party spot keeps a party going (its worker leads it, pick place and size per
  party). Workers keep going while the game is closed as long as your pet's stool lets it. Going on
  an adventure or becoming your active pet takes a pet off its spot. Worker tools: grease for
  everyone (machines), sharper cutters (tables).
- **Open:** spot prices grow fast (placeholders): thousands of workers will need a later layer
  (pets buying machines, "more machines from conquered places").

## Risk and crafting

All opt-in, with odds shown before confirming:

- **Double or nothing** - a glitch treat either upgrades a pet (part, trait, stats or finish) or
  loses it.
- **Fusion** - sacrifice pets to roll a new one, with better odds from rarer inputs.
- **Reroll** - reroll one part or trait; it can come out worse.
- **Crafting** - improve a pet or build gear from loot, with a chance to fail.
- **Grafting** - move a part from one pet onto another; the donor doesn't come back.

## Gear

- **Built (A2):** gear = upgrades to adventuring itself, bought with **xp** (the first thing xp
  buys), on an **upgrades** page inside the adventures tab (adventures | upgrades, the switch shows
  with the first xp). A crayon road snakes through gear stickers in path order; buying one can
  bring the next onto the road (nothing unearned is drawn). Effects show as numbers, like the
  errands pegboard. data/gear.json, `Gear`:
  - comfy boots (trips 8% shorter a level, 5), a tote bag (+15% trip coins, 4), a treat pouch
    (a treat every 13/11/9 s, zoom 9/10/11 s), sticky paws (trail finds +20% and streaks up to
    x1.75/2/2.25), sharper eyes (each bit rolls again at 15% a level; once parts are open, trail
    parts x1.5/2/2.5);
  - once the meadow is open: a lucky charm (+4% a level on options whose failure hurts or loses,
    under the 95% cap; the pet's words shift by themselves, no odds on the trail; gear owns luck
    on risky choices, toys don't), a first-aid leaf (a pet hurt again stays hurt instead of lost:
    one save a trip a level for a solo pet, parties 10% a level for each such pet);
  - with the wheelbarrow (parties of 5): a comfy harness (hurt and lost x 1 - 10% a level).
- Gear is packed when a trip sets off (yours, your pet's and the workers' parties), never in
  dungeons (losses are the cost there). Prices 25-120 xp at x1.6 a level are placeholders until
  the pacing sim (A1).
- Later, maybe: gear bought or gambled (boxes), found on adventures, equipped on pets.

## Economy (first numbers, to be tuned)

- Coins: passive trickle while running, a bigger share from adventures and active play.
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
- Settings has a video page: resolution (the full game is laid out at 920x600 and scaled up to
  1150x750 ... 1840x1200, shrunk to fit the screen if needed), a frame rate cap and vsync.
- Window detection sits behind `scripts/platform/window_source.gd`, one backend per platform.

## Build order

1. **Core: boxes and collection** - rolling pets from parts, opening boxes, the collection book,
   placeholder colours instead of art. (current)
2. Adventures: foraging first; pet narration; exploration and rumours; errands (safe idle jobs);
   party sizes; automation and policies.
3. Care: the desktop pet uses your chosen pet; buffs and check-in rewards.
4. Risk and crafting.
5. Activities: junkyard, NPC trading.
6. Real art, Windows port, Steam.
