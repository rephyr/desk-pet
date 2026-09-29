# Emilia's look picks (2026-09-28, evening)

Picked from the mockups made by the dev-plan run. To be merged into docs/dev-plan.md (the steps'
Prep lines) once that run finishes.

- **B1 shop tiers** (design/mockups/screens/shop-tiers.html): **Look C, today's counter** (a row per
  tier on the counter, a pile per tier in the stash, a per-tier switch on your pet's job card).
  Tier names: **sunny box / sunset box / midnight box** (packs get darker per tier).
- **C1 pets tab** (pets-shelves.html): **Look A, the bookcase** (favourites on a pink cushion on
  top, a plank per rarity with a mound that grows with the count, room as a house meter pill).
- **C3 new homes + sorting rule** (new-homes.html): **Look A, the stall** (stand in the side column:
  tap a shelf, take 1/10/100/all; box jar + starter box pile under it; the rule as a tilted index
  card).
- **B3 automation layer 2** (automation-layers.html): **Look A, the to-do list** (a third button on
  your pet | workers, a list row per job with ticks and tiny crowds, the side card with 'set aside'
  and tools). The find beyond the fence: **a tiny whistle** (the switch says "whistle").
- **F1 sacrifice machine** (sacrifice-reels.html): **Look A, the cabinet** (pink toy slot machine,
  hopper funnel on top, 5 reels, a lever). The part upgrade is called **buttons** (plushie button
  eyes, sewn on one by one). Stuffing's colour: **candy floss coral**. The machine is the
  **plushie machine**, a page in the workbench (toys | plushie machine).
- **D1 knacks** (knacks.html): **Look C, sewn badges** (round badges under the pet, tap to read;
  grid cards get their best badge on the corner). **One knack per part** (the 35 in the page's
  table, slot themes: body = adventures, palette = coins/machine, pattern = finds, eyes =
  spotting, accessory = helping hands; numbers are placeholders for data/knacks.json).

## Details (same evening)

- **B1:** the lucky box is **retired** (one box per tier). Pets per box: **sunny 1, sunset 2-3,
  midnight 2-3**. Finishes: **sunny = shiny, holo, ghost; sunset adds glitch; midnight adds
  prismatic** (glitch and prismatic leave today's starter box). The shop keeps **'inside'
  silhouettes and 'new looks' stickers** (facts on a real pack). Zone 3's name is still open.
- **C1/C3:** the room cap is **one cap for all plain pets together, grown by room upgrades**
  (coins, later the darker currency). The stand pays **points toward a sunny box** (common 1,
  uncommon 2, rare 5, epic 12, legendary 20; 25 points = a box). **Any rarity can go to new homes,
  by hand AND by the rule.** The rule's keeps: a **finish stepper** ("<holo> and up"), new parts
  and favourites always kept.
- **B3:** managing with the whistle **is your pet's one job**. The whistle turns up at **the old
  well, once you have N workers** (like the piggy bank waits for 500 boxes).
- **F1:** an upgrade you didn't hold **auto-banks** on the next spin; anything held when the spins
  run out is banked too. Stuffing's extra reel is **a wild 6th reel** (its button goes to the part
  you pick).
- **D1:** a pet's **finish makes its knacks a little bigger** (e.g. shiny x1.25, holo x1.5).
  **Traits stay** beside knacks (traits per pet, knacks per part). Other pets' knacks help **their
  own trips/jobs a little**. A knack for a system you haven't found yet is **hidden until it
  opens**.

## Brainstorm 2 picks (same evening)

- **A4 book rewards:** the plan's kinds win (coins %, luck, automation speed, errands; written into
  A4 already). **Boosts from different sources multiply.**
- **A5 the machine later: a globe per map page** (sunny today, sunset from beyond the fence,
  midnight from next door: their porch machine comes home as the midnight globe). Each arrives
  broken with a short repair branch (4-6 nodes in machine_tree.json) needing new bits from its own
  page (the fields and orchard start dropping bits), ending in its own rusted hatch (the old
  "better drops": that page's box tier, toys, pet boxes, a bigger coin_value step). **The newest
  globe turns by hand only**; your pet, workers and errands pay at the globe one step behind.
  Not picked: fever for everyone, shiny pet capsules, a floor on the lever. **Fever stays a
  burst** (cap it below the relight time). **The capsule machine shows its odds**, like every other
  machine. Fix docs/design.md's stale "the machine is NEVER automated".
- **B2 multipliers: the receipt by the coin pill** (a small "x1.54" by the pill once a kind has a
  source; tap for a torn-paper receipt ~260x320, by kind, "x1.25" format). **Shared boosts only**
  on it (toys, book stickers, the active pet's badges, the kitchen, later the darker currency),
  plus **"why so much?" tapes** where coins land (postcard, errands pill, machine) for boosts
  inside one system. One GameState plumbing (boost(kind) / boost_parts(kind), a kind table) that
  A5, A4, D1, F2 all go through.
- **C2/F3 spending pets: past the edge first.** At the edge of the beyond page (once every beyond
  place is open, or via a rumour), send pets by shelf; they never come back, the next page fills
  with their scribbles (no outline, a number to go), full = the page opens (~1-2 h of that stage's
  pets/sec, e.g. 500 for next door, then x50-100 a page). Any pet counts the same. The UI word is
  NOT "scouting" (A3 has it). Then **the little school** as the steady drain: classes of spare pets
  stay on as teachers, **every worker (machines too)** gets a bit quicker for good (log-curve class
  sizes, class rarity mix sets the step). **Huge parties can't go down the well line** before
  dungeons (meadow, pond and other risky places only). Settling places is dropped.
- **E2 zone 3: "next door"**: a row of back gardens at night (their gate, garden path,
  greenhouse, pond, porch with a broken machine, the doghouse as the risky spot), recoloured
  backyard doodles with little lit windows that go dark one visit at a time. **Opens by pets past
  the edge** (so next door + the midnight box arrive in stage 3). **Places become "ours" after
  enough visits, the backyard too** (the pet colours the doodle in, safer, pays a bit more, locals
  stop turning up; high N for the backyard). Locals only ever as traces.
- **The pet's possessive slips get cut** ("i mean, we should visit!" in unlocks.json, "mine now.
  i mean ours!" in voice.json).
- **E1 first dungeon: the old well, all the way down.** Bands: the well (floors 1-10, rope floors
  where only the front row climbs), the cellar (11-20, doors, tiny doors only rare+ fit through,
  knock-back doors test luck), further down (21+, stairs forever, a guard every 10th). The top of
  the well stays a trip (the whistle is found there); cellar/below become bands already reached,
  never removed from old saves. Opens with a find at the well ("the rope goes further down",
  min_party ~100, after the whistle). Floor strength ~100 x 1.2^n. **Front row + tiny doors:**
  your best ~20 card pets fight, the herd walks behind as reserves. The entrance fits 300 at first
  (widening = the first lantern buy; bounds "sent" for lanterns). Floor 10 = the first dungeon
  part + your pet learns "lead the army"; floor 20 = the key to E3. **Orders: the orders card**
  (sentences with steppers like the sorting rule; "go down to floor ‹10›", "come home when ‹30%›
  are gone", more lines earned per floor kind, e.g. "who goes first ‹plain ones›"). Lives as a
  third page in adventures (adventures | upgrades | dungeon). Floor strength never shown as a
  number (feeling words). Needs C3's herd first.

## Balance picks from the A1 pace report (lanes/sim, docs/reports/pace.md)

- **Errands earn about 1-3x the lever** (apply the sim's tweak "C": lemons/noses/bigger_jar grow
  1.5, paws + sign speed 0.04, pockets big 0.05, snack all_speed 0.03, coin hunt + lemonade goals
  x1.25 / 1.25 / 1.5).
- **Errand tools and boxes are priced in capsules** (cost x Machine.coin_value, like their pay):
  its own small step, fixes the drift and the box flood.
- **Your pet's crank ~1-2% of the lever** (machine job seconds 48 -> 15).
- **Apply the sim's other numbers in the merge**: automation prices (~x100, table in the report),
  auto_adventures trips 60 -> 30, garden -> pond spot 0.3 -> 0.6. Then re-run the sim on the
  merged game and report the new curve.

## Merge run to-do (Claude)

- Tool scripts (-s) must never save: GameState `_can_save = false` when a tool script is the main
  loop. Checks line in CLAUDE.md: `godot --headless -s tests/test_core.gd -- --profile=core-test-main`.
- Old rule breaks seen in screenshots: a locked "???" tab in the sidebar; the errands board's "?"
  card ("something behind the shed...") and hint text under the errands title; map lead labels
  cut off at the edges ("gears out this way?", "bolts out this w"), "the garden path" label under
  the speech bubble; errands header ellipsis.
- More '???' placeholders to remove: the errands pegboard shows '???' tags for closed tools
  (errand_tools_view.gd); the spine's locked tab; collection_tab.gd:152.
- Open question for later: the welcome-back payout scales 200 rolled capsules up to every pull
  (one lucky golden can be multiplied thousands of times).
- Follow-up step idea: a GameState clock (now()/tick) so the pace sim stops copying rules.

## Look picks, round 2 (mockups in lanes/mockups: globes, receipt, past-the-edge, next-door, dungeon)

- **A5 globes: Look A, side by side** (sunny globe with a worker hanging off its lever + the big
  broken sunset globe, a 'sunset fixes' list; the sunset branch grows off the old rusted hatch in
  the same tree). **The older globe is workers only**; your hand is for the newest. New bits:
  **corks, pulleys, copper wire, amber glass** (orchard: corks + amber glass; old well: pulleys;
  far fields: copper wire). Bits pills show the newest globe's bits.
- **B2 receipt: Look A, the dark till roll** (dashed cyan 'x1.51' pill by the coin pill, a dark
  torn receipt 'our boosts' printed from a slot, a header per kind with totals, dotted-leader
  lines, 'thank you, come again' + barcode; a pink washi 'why so much?' tape on the postcard's
  coins opening a small torn slip: found 47, tote x1.30, our boosts x1.51, all together 92).
- **C2 past the edge: Look A, the tucked page** (the beyond map's torn right edge with a signpost
  spot called **"the edge"**, the next page tucked under it filling with crayon scribbles in the
  pets' colours, 'N to go'; side card lists shelves, 1/10/100/all). **The little school: Look A,
  the classroom** (a 'school' button next to your pet | workers | whistle, a chalkboard 'class 4
  +3.2%', 24 desks filling, finished classes in a 'teachers' row; class sizes 40, 100, 220, 450,
  900...; classes multiply). **The sorting rule can send pets to school; you ring the bell
  yourself** when a class is full.
- **E2 next door: Look A, the street** (a row of house backs along the top, their windows are
  the lights, one goes dark per visit; when the last goes out the garden is coloured in and a flag
  goes on the roof; picket fences between gardens, one path in through their gate). **Your pet
  colours taken places in its own colour** (lilac blob = lilac). Places: their gate, garden path,
  greenhouse, pond, porch (broken capsule machine), doghouse (risky); lights 3/4/5/5/6/8
  (placeholders); the gate and path start as ours. Locals only as traces.
- **E1 dungeon: Look A, the cross-section** (the well as a tall scrolling column: rope floors
  1-10, cellar 11-20 with tiny doors on 13/17 and knock-back doors on 15/19, stairs further down
  with a guard every 10th; the army in the middle: front row of 20 card pets in a 7-wide grid with
  your pet's flag, the herd mound + shelf steppers, entrance meter 282 / 300; side column: the
  orders card + a 'last time' card). Feeling words for floors (easy peasy, a stroll, comfy, spooky,
  tricky, so tough, brr!). 'who goes first: plain ones / anyone / the front row'. **The E3 key on
  floor 20 stays fully hidden** until found.
- **Lanterns and stuffing are ONE darker currency** with two sources (dungeon floors, plushie
  machine misses), candy floss coral. Name still open.

## Brainstorm 3 picks (2026-09-29, night)

- **E3 the hard dungeon: the sewing room**: a side door on well floor 20 (tap it and the
  cross-section pans sideways); ~8-10 rooms (button tin, pin cushion, thread maze, ribbon drawer,
  the big scissors), each with a strength (E1's army maths) AND a chalk-drawn lock: part pictures
  for named D1 knacks (halos, bunny ears, horns), trait icons, finish swatches, rarity colours;
  each drawing fills in as a front-row pet matches it (no text); tapping an unfilled mark shows
  where it comes from (like bit_hint). No holders line. The first clear teaches the sorting rule
  **keep lines, capped** (each keeps the last ~50 matching pets as cards). **The last room gives a
  working plushie machine and sews one free button onto your active pet.** After F1, rolled rooms
  farm forever with **button locks** (same lanterns as the well).
- **The darker currency is called "wisps"** (candy floss coral; lanterns and stuffing are wisps
  from two sources). **The perk tree lives on the well wall**: coral things (a flag, a bell, a
  spool, a nightlight) hang on nails on the dungeon's landings, deeper nails show once the army has
  been that deep; tapping a nail puts its card in the side column. The widened entrance is the top
  nail (the first buy). **A finite tree + 2 endless tips** (coins, pets/sec, +3-5% a level at x3
  the price). Plushie perks hang there too, hidden until the machine opens.
- **Room upgrades: the house card**, from the bookcase's room pill: a cut-away house picture per
  step (a second plank, bunk beds, a loft, the attic); coin steps first (cap x1.5 each, priced in
  capsules), then wisp "squeeze in" steps (x2 cap); each step is ONE currency. **Every plain pet
  counts toward the room, pets on jobs too.**
- **F3 spending pets: the wish list, then the shed workshop, then held landings** (no pillow).
  The wish list: pin one look you've seen in the book, send pets by shelf to fill pages (200, 600,
  2k, 6k), each full page raises that look's weight inside its already-rolled tier; **it steers
  every box** (your rips, your pet's, the box tables); rarity never moves; needs its own picture
  and word (not "pages": the edge and the book already use that). The shed workshop: once the
  old shed is ours and the whistle is found, tap the shed on the backyard map; drawings are built
  by crowds of pets with a rarity need, **pets only** (no wisps), each takes away an old chore.
  Held landings: crowds hold well landings 10/20/30..., armies can start from the deepest held one
  (skipped floors pay no lanterns).
- **Stars: only pets that leave or are lost** add a night-sky star. Pets who stay on for good
  (school teachers, workshop helpers, landing holders) do NOT (fix C2's teachers in the merge).
- **Care: A, then E, then C.** A: care becomes buffs: food and mood **freeze while the game is
  closed**; the kitchen keeps food up to 70; above 70 = full tummy coins x1.2, happy luck x1.1
  (through the B2 boost plumbing, on the receipt); an empty bowl is just no bonus, never a sad
  pet; **snacks cost capsules**; the old coin trickle goes; design.md's "+50% for 2 h" changes.
  E: quiet paws: out on your windows your pet keeps doing its one job with **poses only, no
  text** (opens a box on a window edge, holds up a good pull 4 s, taps its foot when an adventure
  waits); **setting: off / big things / everything** (not a second box-opening switch). C:
  presents: one every 3 h of wall clock, a pocket of 3, from when the boxes tab opens; **boxes of
  your newest tier + sometimes a toy capsule, never bits, never a pet**; out on your windows your
  pet digs the present up and wears it until you tap it.

## Small open questions collected from the lanes (ask Emilia after the merge)

- Plushie: the keeper can't go on adventures while it's in the machine; banked reels stay banked
  across a keeper swap; a keeper with 'no accessory' still spins the accessory reel (skip it?);
  the card picker pages 20 at a time (or group by rarity?).
- Prices: the box reserve shows as coins (or 'keep N boxes'?); a starter box = 50 capsules when the
  shop opens (too steep?).
- A2 gear: the leaf saves only from 'hurt', not 'lost'; the harness shows at the wheelbarrow.
- A3: a floor on the kitchen's bonus at huge crews? A4: several full book pages at once queue
  their sticker popups one by one (or one popup?).
- C2: a page's need lowered below what a save already sent: carry the extra pets on to the next
  page (current) or drop them? Teachers must stop adding stars (merge fix, per Brainstorm 3).
- E1: floor 10's epic part waits until parts open (40 trips) and its glint stays hidden until
  then (or give it straight away?).
- B1: after long away, box workers open at most 2000 boxes at load (rest wait on the pile).
- B3: the whistle fills parties first and keeps a crew free for each (or machines first?).
- B2: should automation speed also speed automated adventures? Should gear count as a shared
  boost on the receipt?
- A5: once the sunset globe is home, its later fixes show by name and cost (dim), like the
  mockup (or "?" until the one before is fixed? note the "no ??? placeholders" rule). Bits pills
  show only the bits open upgrades need (or every bit you own?). The globes flow failed once in
  ~12 runs ("4 resources still in use at exit"): watch it in the merge.
- B2 receipt: a prize draws over the open machine slip and the slip stays open after the pull.
  The tag shows only once COINS has a source (an active pet with only non-coin badges shows no
  receipt): OK? Existing: the trip postcard grows under the 'away' column with 3 part cards.
- E2: two or more trips back share one tag "N parties are back!". The slipper trace moved to the
  porch steps (the gate and path start as ours).
- Existing: sunny tree node labels overlap/cut off at this window size ("triple drop"/"double
  drop", "a second chute"/"third chute").

## Look picks, round 3 (mockups in lanes/mockups2: well-additions, wish-list, shed-workshop, room-house)

- **Well additions: Look A, on the walls** (everything drawn on the column at once in lanes:
  coral things on nails down the left soil lane joined by a coral thread, solid down to the last
  bought, dashed chalk after; the bow on the roof post = the entrance; crowds + count pills on
  landings 10/20/30; the 2 endless tips at the bottom). **The perk tree is a chain**, each thing
  needs the one above; **the 2 endless tips open once the chain is done**. Unbought things show as
  dashed outlines; nails below the deepest floor reached stay fully hidden. Names from the mockup
  (woolly scarf, nightlight, dinner bell, lunchbox, pinwheel, music box, paper star, lucky coin,
  rattle).
- **The wish list: Look A, the wishing jar** (a jar sticker in a side column beside a narrower
  book spread, the wished sticker as the label, pets fill it with dots in their colours, 4 bands,
  a gold star per full step, the lid glows when done; 'N / M', shelf chips, 1/10/100/all). Steps
  200/600/2k/6k each (8,800 in all), **every pet counts 1**, switching the wish keeps the old
  one's filled steps, no finishes, it ends after 4 steps.
- **The shed workshop: Look A, the card on the map** (tapping the shed sticks a workshop card on
  the backyard map, 3 drawings pinned on a plank with progress bars, the picked one's needs as
  helpers + rarity bars, 1/10/100/all, 'not yet' / 'build it!'; built things stand around the
  backyard). **All 3 pinned drawings fill at once; you tap 'build it!'.** Chores that are manual
  on purpose stay manual (the weather vane only answers plain trip choices; the school bell and
  reel banking stay yours). The 8 drawings from the mockup table as the start (tune later).
- **The room house: Look A, the dollhouse** (one cut-away house that grows, the next step drawn
  in pencil inside it, a 'next up' row with the room growing and 'build it' / 'squeeze in'; chips
  for shelves and jobs counts). **Wisp squeeze-in steps keep going** (pets in the teapot, under the
  rug...); coin prices grow with capsule value like errands; sizes set by the pace sim.
- Care: pats give +8 mood at most once every 30 s (longer cooldown or a daily cap?); care buffs
  never count for closed time; the kitchen now multiplies errand speed (was additive); the
  automation sticker also speeds on-screen box opening. Quiet paws needs ~92 px beside the pet.
