# Desk Pets - development plan

The whole game, as steps we can build one at a time. Written 2026-09-28 from Emilia's design notes
(docs/design.md, the memory notes: stages, core loop, automation, adventures, theme) and what's
built. **Update this file whenever a step is done or a decision is made.**

How a step works:
1. **Prep** (with Emilia): answer the step's open questions, pick a mockup look (2-3 looks in
   design/mockups/, screenshots). A step with nothing left in "Prep" is **ready**.
2. **Build** (Claude): the plan is in the step; a short plan check with Emilia before coding.
3. **Done when**: tests pass (tests/test_core.gd), a flow in tests/flows/ plays it with
   screenshots, `expect fits` holds, docs and CLAUDE.md updated, committed and pushed to `test`.

## Brainstorms (DONE 2026-09-28)

The four brainstorms ran (workflow: brainstorm, critique, tie together) and Emilia picked. Her
picks are written into A2, C3, F1 and F2 below. Options she didn't pick are in
docs/brainstorms.md, in case they're wanted later.

1. **More gear upgrades** → A2 (all 8 upgrades picked).
2. **Bad pets** → C3 (work, then the new homes stand, then feed the sacrifice machine; the herd;
   room cap + sorting rule).
3. **The new layer** + 4. **the darker currency** → the **"stuffed toys" bundle**, F1/F2: reels
   put upgrades on the keeper's parts, dungeons pay lanterns, misses puff stuffing (working names).

Rules every step follows: the game never winks (cute voice, darkness only in what you do);
show, don't explain (no hint text about mechanics); hidden until earned (no locked "???"
placeholders); UI never spills past the 920x600 window; no dropdowns; no "·" separators; dark
apps; keep Emilia's names for things; pets are lost only by choice; always something manual to
do, and always an irritant to wish away.

The main goal never changes: **"I want a good, rare pet."** The side goal changes per stage.

---

## Where we are

Built (see CLAUDE.md "Where we left off"):
- **Stage 1, early-early:** tutorial, the capsule machine and its repair tree (bits from
  adventures), backyard + beyond-the-fence map pages, errands with upgrades (the idle coin maker
  and coin sink), capsule toys + the workbench, rummaging, boxes (the pack ritual), pet boxes.
- **Automation layer 1:** your pet does one job (crank its own machine, run adventures, open
  boxes), taught with coins; the workers page (teach the others, bought spots, you assign).
- **On test (2026-09-28):** A2 gear, A3 more errand jobs, A4 book rewards (save v24).
- **Merged in lanes/merge (2026-09-29, goes to test once the merge passes):** X4 tests, A1 pace
  sim, PRICES (save v25), B2 boost plumbing + D1 knacks, B1 box tiers + the small picks (save
  v26), B3 the whistle (save v27), C1 the bookcase + the herd + C3 new homes (save v28), the round 2
  mockups.
- Tools: tests/test_core.gd, tools/play.py flows, tools/balance.gd, tools/pace.gd (A1),
  tools/machine_pace.gd.

**Lanes (2026-09-29):** steps are built in parallel in git worktrees under
~/projects/desk-pets-lanes/ (branches `lanes/<name>`), each writes docs/plans/<STEP>-done.md,
and `lanes/merge` merges them one by one (save versions renumbered in merge order). Built in a
lane and verified there, **not merged yet**: A5 sunset globe
(`lanes/globes`), E2 next door (`lanes/nextdoor`), C2 past the edge + the school (`lanes/edge`),
E1 the dungeon (`lanes/dungeon`), F1 the plushie machine (`lanes/plushie`), care A/E/C
(`lanes/care`), room upgrades / the dollhouse (`lanes/house`), E3 the sewing room + the perk
wall (`lanes/sewing`), F3 the wish jar (`lanes/wish`) and the shed workshop (`lanes/workshop`),
round 3 mockups (`lanes/mockups2`).

Known small open items: the "new: the bag!" popup can land on the trip postcard; balance note (a
huge scrapyard crew floods the bag); the sunny tree's node labels overlap at this window size
("triple drop" / "double drop", "a second chute" / "third chute"); the welcome-back payout scales
200 rolled capsules up to every pull (one lucky golden can be multiplied thousands of times).

---

## Phase A: finish the early game (stage 1 → 2)

### A1. Pacing simulator for the whole early game  (BUILT, merged; report in docs/reports/pace.md)
- **Why:** automation, errands and the tree all pay in capsules now; nobody has checked the curve
  end to end. Emilia is testing timing by hand.
- **Build:** extend tools/machine_pace.gd (or a new tools/pace.gd) to play a simulated player:
  pull rate, repairs, errands levels, automation jobs, workers. Print minute-by-minute milestones
  (repairs, errands, better drops, automation, first worker) and coins/min per source. Suggest
  prices for data/automation.json.
- **Done when:** a report Emilia can read, with suggested numbers (not applied until she says).
- **Built (2026-09-28, lane sim, plan in docs/plans/A1.md, notes in A1-done.md):** `tools/pace.gd`
  + `tools/pace_player.gd`: pretend players (steady / casual, `--treats`) on the real GameState
  with a sim clock; milestones, coins/min by source, gate waits; `--tweak=<path>=<value>` tries
  numbers in memory. Run: `godot --headless -s tools/pace.gd -- --profile=test-sim --runs=5`.
  Report: docs/reports/pace.md. Findings: errands earned 10-50x the lever (stacked multipliers;
  tools priced in coins, pay in capsules); bits are the only gate on the tree (coins never wait);
  the pond opens late (glass); 50-coin boxes flooded pets; automation is bought the minute it
  opens and paid ~1% of the lever; 60 trips isn't reached in 4 h. The copies in pace_player.gd
  (`_automation`, `_zoom`, `_passive`, moved timestamps) are kept in step with GameState by hand.
- **Emilia's balance picks (2026-09-28, docs/picks.md):** errands earn about **1-3x the lever**
  (the sim's tweak "C": lemons/noses/bigger_jar grow 1.5, paws + sign speed 0.04, pockets big
  0.05, snack all_speed 0.03, coin hunt + lemonade goals x1.25 / 1.25 / 1.5); **errand tools and
  boxes priced in capsules** (DONE, see PRICES); your pet's crank ~1-2% of the lever (machine job
  seconds 48 -> 15); automation prices ~x100 (table in the report); auto_adventures trips 60 ->
  30; garden -> pond spot 0.3 -> 0.6. **Still to apply** (everything except the capsule prices),
  then re-run the sim on the merged game and report the new curve.
- Follow-up idea: a GameState clock (now()/tick) so the pace sim stops copying rules.

### A2. Gear: xp upgrades  (BUILT + VERIFIED 2026-09-28)
- **Emilia:** an "upgrades" page INSIDE the adventures tab (adventures | upgrades, like machine |
  upgrades), not its own tab. Look: gear.html's crayon path of gear stickers, words not numbers.
  Opens with the first xp. First upgrades: **walk speed** (shorter trips), **bigger bags** (more
  coins/loot home), plus the ones brainstorm 1 picks.
- **Look (picked 2026-09-28):** gear.html's crayon path (stickers along a path, buying reveals the
  next ones), but **effects show as numbers** ("trips 10% shorter"), like the errands pegboard.
- **The upgrades (Emilia picked all 8, 2026-09-28).** Nothing spends xp yet; a garden trip gives
  ~11 xp, so prices of 25-120 xp at x1.6 a level (as in gear.html) fit. Path order:
  - early (garden/backyard): **comfy boots** (AdventureRunner.gap() x (1 - 0.08/lv), 5 levels,
    "trips 8% ... 40% shorter"), **a tote bag** (trip coins +15%/lv, 4 levels, in
    _boost_trip_loot; coins only), **a treat pouch** (TREAT_EVERY 15 → 13/11/9 s, TREAT_ZOOM 8 →
    9/10/11 s; the consts become functions), **sticky paws** (trail pickups +20%/lv and
    STREAK_MAX 1.5 +0.25/lv, 3 levels; replaces "bigger basket": worth more, not more clicks),
    **sharper eyes** (bits, then parts: _finish_treat rolls each bit again at 15%/lv, 3 levels;
    once feature:parts is open the trail's part weight goes 4 → 6/8/10. NOT spotting/rumours:
    scouting A3 and the big ears knack own those).
  - once the meadow (first place that can hurt) is open: **a lucky charm** (+4%/lv on options
    whose failure hurts or loses, 3 levels, under MAX_CHANCE 0.95; PetVoice's words shift by
    themselves, no odds shown). **Gear owns luck on risky choices**, toys don't (toy luck stays on
    the machine and extra loot). **A first-aid leaf** (1 save per trip per level: a pet hurt a
    second time stays hurt instead of lost; parties save level x 10%; covers "trail snacks", the
    trail's heal pickups stay the manual version).
  - late, near parties and swarms: **a comfy harness** (hurt/lost x (1 - 0.1/lv), 3 levels).
- **Reach:** gear works on your trips AND auto parties (your pet's and the workers'), **never in
  dungeons** (losses are the cost there). The A1 sim must count boots and the pouch.
- Dropped: more trip slots (there is no cap to sell back), a little map (the automation job's
  work), a bigger basket (→ sticky paws), a bit pouch (→ sharper eyes).
- **Build:** data/gear.json, a pure Gear rules class, GameState xp spending, a GearView page in
  AdventuresTab, flow.
- **Built (2026-09-28, plan in docs/plans/A2.md):** data/gear.json (8 upgrades, base values,
  prices = xp x 1.6^level), `Gear` (scripts/adventure/gear.gd), `GameState.gear` (save v22 field
  "gear"; buy_gear / gear_block / gear_price / shown_gear / gear_page_open), `RunState.gear` (the
  levels a trip packs when it sets off, `Gear.for_trip`: never in dungeons) and `RunState.saves_used`
  (the leaf), `GearView` (the crayon road of stickers + card) behind an adventures | upgrades
  switch that shows with the first xp. Effects: boots in `AdventureRunner.gap` (`run_gap`), charm in
  `success_chance` (risky options, not at safe places), harness + leaf in `play` / `Party.hurt`,
  eyes in `_finish_treat` and the trail's part weight, tote in `_boost_trip_loot`, pouch in
  `treat_every` / `treat_zoom`, paws in `trail_pickup` / `streak_max`. Dev steps `xp <n>`,
  `gear <id> [levels]`, `page <tab> <n>`, `place <id>`; flow gear; tests `_test_gear`.
  **Open questions for Emilia:** see docs/plans/A2.md (leaf only saves from "hurt"; harness shows
  with the wheelbarrow; gear packed at set-off; the charm's card shows +4%; prices placeholders
  until A1).
- **Verified (2026-09-28):** flow gear passes (`expect fits` on the page), tests pass; fixes from
  the check: sticker rows taller (an effect that wraps to 3 lines kept its price inside the window),
  the tote's "bought" line says coins (it only boosts coins).

### A3. More errand jobs  (BUILT + VERIFIED 2026-09-28)
- **Emilia picked:** savings jar (fills slowly, pays one big chunk), kitchen (brings nothing,
  every job a bit faster, SOFT: a few cooks ~+10-25% diminishing, never beats real jobs; feeds
  your pet), scouting (raises the spot/rumour chance of the next trips; CHANCE ONLY, the map's ?
  clouds stay a surprise).
- They open through **goals on job levels**, like the lemonade stand (e.g. lemonade lv 10 → the
  savings jar; coin hunt lv 25 → the kitchen; a later goal → scouting).
- **Built (2026-09-28, plan in docs/plans/A3.md):** data/errands.json jobs `jar`, `kitchen`,
  `scouting` (per-job `crew_power`, `chunk`, `kitchen`, `scout`, pay kinds `meal` / `note`, tool
  effect `hold`, `share: false`, goals with both `x` and `text`), unlocks `jar` (lemonade lv 10),
  `kitchen` (coin hunt lv 25), `scouting` (savings jar lv 10). `Jobs.kitchen_bonus / scout_hold /
  scout_job / scout_note / feed / takes_note / shared_out`, `GameState.scout_notes` (save v23) / `kitchen_bonus()` / `scout_full()`,
  `send_on_adventure(..., by_you)` takes a note (`RunState.scout`), `Intel.roll` bonus +
  `Intel.left_to_find`, `AdventureRunner.scouted` (rumours x1.5). Errands tab: jar / kitchen /
  scouting note lines, big gold pop + coin burst for the jar, waiting notes and shelves only for an
  open job's next goal, long job names wrap. Offline food drop now runs before the errands catch
  up (meals made while away count; meals only fill food up to `meal_upto` 70). Dev steps `job <id> <n>`, `notes <n>`, `scroll <px>`; flow
  errand_jobs; tests `_test_more_jobs`.
  **Open questions for Emilia:** see docs/plans/A3.md (scouting opens at jar lv 10; auto parties
  never take notes; kitchen has no floor at big crews; share out skips kitchen + scouting; hold 2
  notes; no away bonus for the jar; all numbers placeholders).
- **Verified (2026-09-28):** tests + flow errand_jobs pass, UI fits. Fixes from the check: the
  kitchen's line keeps one decimal when a big crew elsewhere thins it out ("every job 0.4%
  faster", `Jobs.faster_words`, never "0% faster"), and sending a trip skips the "anything left to
  find?" look for auto parties (`GameState._place_known`).

### A4. Book page rewards  (BUILT + VERIFIED 2026-09-28, mockup design/mockups/screens/book.html)
- Filling a collection book page opens its reward sticker: a **small permanent boost** (the book
  becomes a multiplier source). Kinds: **coins %, luck, automation speed, errands**.
- **Emilia (2026-09-28, evening): the kinds above win over book.html's stickers** (the mockup's
  rest faster / shinies / trail grabs / spotting / bag room / finishes are OLD). Spread the 4 kinds
  over the 6 pages (bodies, palettes, patterns, eyes, accessories, finishes; a kind may repeat).
  Keep book.html's sticker look and object names where they fit, but never "sticky paws" (that's
  a gear upgrade now). **Boosts from different sources multiply** (toys x1.25 x book x1.10 =
  x1.375), like toys already stack.
- **Built (2026-09-28, plan in docs/plans/A4.md):** data/book.json (`words` per kind with `{p}`,
  6 `pages` of `{id, slot | finishes_of, name, kind, x}`: bodies a cozy blanket automation,
  palettes a paint set coins, patterns a roll of washi tape errands, eyes a magnifying glass luck,
  accessories a little wardrobe errands, blob finishes a glitter jar coins; all x1.10,
  placeholders). `Book` (scripts/pets/book.gd, pure rules), `GameState.stickers` (save v24, kept
  for good even when a page gains parts later) / `check_book()` (on pets_added and after load:
  old saves open already-full pages with their popups) / `sticker_opened`; the stickers are the `book`
  source of the B2 boosts (`Book.parts`): coins and luck everywhere `boost()` is read, errand
  speed (`job_rate`, offline too), automation speed (your pet's crank, the workers, box opening;
  not auto adventures). Book: the reward tile ends each
  sticker page (dashed gift spot with no words, then the gold sticker tilted 2 degrees), popup "<page> page
  full!" with "show me" (opens that spread) / "lovely". Dev steps `book <page> [left]` and
  `stickers off` (big `pets` steps fill random pages: errands_crowd, errand_jobs, workers, fits use it); flow book;
  tests `_test_book`.
  **Merge fix (B1 x A4):** a page only counts looks from box tiers in the shop (`Book.keys(..., rank)`,
  `GameState.book_rank`), and the book hides the rest until found: the midnight looks (dragon,
  midnight, halo, prismatic) made 4 of 6 stickers unearnable before next door.
  **Open questions for Emilia:** see docs/plans/A4.md (only blob's finishes page has a sticker;
  kinds per page and +10% each; washi tape name; what errands / automation cover; the dropped "fill
  the page for a surprise" line; numbers instead of words; old saves get their popups on load).
- **Verified (2026-09-28):** tests + flow book pass (every spread `expect fits`), and the flows
  whose big `pets` steps now fill pages (errand_jobs, errands_crowd, workers, fits) pass with
  `stickers off` / closing the popup.

### A5. The machine's later ideas  (DECIDED; sunset globe BUILDING in lane globes, not merged)
- Rummaging → machine bits, pull value grows with income, a globe per map page, "better drops"
  mystery balls. **Prep:** which of these still matter now that automation exists.
- **Emilia picked (2026-09-28, docs/picks.md): a globe per map page** (sunny today, sunset from
  beyond the fence, midnight from next door: their porch machine comes home as the midnight
  globe). Each arrives broken with a short repair branch (4-6 nodes in machine_tree.json) needing
  new bits from its own page, ending in its own rusted hatch (the old "better drops": that page's
  box tier, toys, pet boxes, a bigger coin_value step). **The newest globe turns by hand only**;
  your pet, workers and errands pay at the globe one step behind. Not picked: fever for everyone,
  shiny pet capsules, a floor on the lever.
- **Look A, side by side** (sunny globe with a worker hanging off its lever + the big broken
  sunset globe, a "sunset fixes" list; the sunset branch grows off the old rusted hatch in the same
  tree). **The older globe is workers only**; your hand is for the newest. New bits: **corks,
  pulleys, copper wire, amber glass** (orchard: corks + amber glass; old well: pulleys; far fields:
  copper wire). Bits pills show the newest globe's bits.
- Done already (small picks): fever stays a burst, the capsule machine shows its odds, design.md's
  stale "the machine is NEVER automated" fixed.

---

## Phase B: stage 2, coins get semi-automated → chase packs and a rare pet

### B1. Pack tiers per map page  (VERIFIED 2026-09-28, merged, save v26)
- **Decided:** ~x5-10 cost per tier; a new tier appears in the shop when its **map page opens**
  (backyard tier 1, beyond the fence tier 2, zone 3 tier 3). A higher tier has ALL of: better
  rarity odds, more pets per box (2-3), gated finishes (some only from a tier up), gated parts
  (some body parts/palettes only exist from a tier up: new looks to collect).
- **Emilia picked (2026-09-28):** look C, today's counter (a row per tier on the counter, a pile
  per tier in the stash, a per-tier switch on your pet's job card). Names **sunny box / sunset box
  / midnight box** (packs darker per tier). The lucky box is retired (one box per tier). Pets per
  box: sunny 1, sunset 2-3, midnight 2-3. Finishes: sunny = shiny, holo, ghost; sunset adds
  glitch; midnight adds prismatic. The shop keeps "inside" silhouettes and "new looks" stickers.
- **Build:** data/boxes.json tiers, gating in PetRoller, the boxes tab shelf, balance numbers.
- **Built:** sunny / sunset / midnight boxes (data/boxes.json: page, stamp, pets, arrives; priced in
  capsules 50 / 400 / 3200 through GameState.box_price), gated finishes and new looks (parts.json
  `from`), lucky box retired (BoxShop.fix_retired on every load: lucky -> sunset; save v26 adds
  boxes_bought + boxes_greeted), look C shop (counter row per tier with stamp, new looks stickers,
  inside shapes; stash pile per tier; a switch per tier on the job card), a tier pops in once with a
  sparkle + "new!" until bought, one box with 2-3 pets = ritual for the best + "also inside",
  workers count boxes. Midnight waits for the next-door page (E2). Flow box_tiers. Questions for
  Emilia in docs/plans/B1-done.md.

### B2. Multipliers  (plumbing BUILT, merged; receipt BUILT, merged)
- Book page boosts (A4, decided), knacks from the active pet's parts (D1, decided: knacks),
  toys (built), finds. Income must keep growing. **Prep:** where the player sees them all.
- **Emilia picked (2026-09-28): the receipt by the coin pill**, look A, the dark till roll: a
  dashed cyan "x1.51" pill by the coin pill once a kind has a source; tap for a dark torn receipt
  "our boosts" (~260x320) printed from a slot, a header per kind with totals, dotted-leader lines,
  "x1.25" format, "thank you, come again" + barcode. **Shared boosts only** on it (toys, book
  stickers, the active pet's badges, the kitchen, later the darker currency), plus pink washi
  **"why so much?" tapes** where coins land (postcard, errands pill, machine) for boosts inside
  one system (e.g. found 47, tote x1.30, our boosts x1.51, all together 92). **Boosts from
  different sources multiply.** One GameState plumbing that A5, A4, D1, F2 all go through.
- **Built (lane b2-d1, merged):** B2 boost plumbing: `GameState.boost(kind)` /
  `boost_parts(kind)`, `Boosts` + data/boosts.json kind table, `toy_boost` removed. Sources: toys,
  the book's stickers, your active pet's knacks, the kitchen (errand speed; it multiplies now
  instead of adding to the tools' speed, so it's worth more with lots of tools). Kind `automation`
  = automation speed (crank, box opening, workers; not adventures).
- **Built (B2UI, lane receipt, merged):** the receipt, look A (the dashed "x1.51" tag by the coin
  pill, the dark torn receipt "our boosts" by kind, shared boosts only) and the "why so much?"
  tapes on the postcard's coins, the errands pill and the machine's capsule line. Book stickers
  ("a paint set") and the kitchen are named on it through `GameState._boost_line_name`. No save
  change. Open questions for Emilia in docs/plans/B2UI-done.md.

### B3. Automation layer 2: pets restock and buy spots  (BUILT + VERIFIED, merged, save v27)
- **Emilia:** workers can open boxes but not buy them, machines must be bought and filled by hand
  (the irritant). Layer 2 removes those chores: the piggy bank already lets your pet buy boxes;
  next something that buys machines and puts new pets on them.
- **Decided 2026-09-28:** unlocked by **a find beyond the fence** (like the piggy bank; e.g. a
  clipboard: your pet can manage workers). **Lore: machines come from places you've taken**: old
  machines left in places your pets "visited", coins haul them home, each map page raises how
  many exist (invading and automating feed each other).
- **Prep:** the look (a layer switch on the automation tab), the find's name.
- **Emilia picked (2026-09-28):** look A, the to-do list (a third button on your pet | workers, a
  list row per job with ticks and tiny crowds, the side card with "set aside" and tools). The find
  is **a tiny whistle** (the switch says "whistle"). Managing with the whistle **is your pet's one
  job**. The whistle turns up at **the old well once you have N workers**.
- Also: spot prices must flatten so thousands of workers are possible.
- **Built (2026-09-28, lane b3, notes in docs/plans/B3-done.md):** the whistle (look A, the to-do
  list): a find at the old well after 30 workers, a third switch button, managing is your pet's one
  job, haul / fill ticks per job, set aside, pencil + wagon, caps per map page (parties one per
  place), flattened spot prices, offline with the stool. Save v27 (automation.whistle, additive).
  Open: the numbers (30 workers, caps, set aside, prices) are placeholders; the pace sim doesn't
  play the whistle yet.

---

## Phase C: stage 3, pack opening gets automated → managing pets

### C1. The pets tab as containers  (BUILT + VERIFIED, merged; the herd is save v28)
- **Emilia:** sections are **automatic, by rarity** (a shelf per rarity with a count, tap to open
  it), with favourites / the best ones **pinned at the top**. Needed before thousands of pets.
- **Emilia picked (2026-09-28):** look A, the bookcase (favourites on a pink cushion on top, a
  plank per rarity with a mound that grows with the count, room as a house meter pill). The room
  cap is **one cap for all plain pets together, grown by room upgrades** (coins, later the darker
  currency).
- **Room upgrades (picked 2026-09-29): the house card**, from the bookcase's room pill: look A, the
  dollhouse (one cut-away house that grows: a second plank, bunk beds, a loft, the attic; the next
  step drawn in pencil inside it; a "next up" row with "build it" / "squeeze in"; chips for
  shelves and jobs counts). Coin steps first (cap x1.5 each, priced in capsules, growing with
  capsule value like errands), then wisp "squeeze in" steps (x2 cap) that keep going (pets in the
  teapot, under the rug...); each step is ONE currency; sizes set by the pace sim. **Every plain
  pet counts toward the room, pets on jobs too.** BUILDING in lane house, not merged.
- **Built 2026-09-28 (lane c1-c3, notes in docs/plans/C1-done.md):** look A, the bookcase: cushion
  (active, favourites, best), a plank per rarity (tag, newest 4, a mound that grows with the count,
  shiny count, the best knack's badge on each card's corner), a shelf opened (herd chips,
  always-cards, newest 20, sticker with heart + make active), the room pill.

### C2. Pets per second  (DECIDED; past the edge + the school BUILDING in lane edge, not merged)
- **Emilia:** once opening is automated you get pets per second; pets become the midgame
  currency. Shown as **a pill at the top of the automation tab** ("N pets a minute"), like errands'
  coins a minute, once box workers exist. **Prep:** what spends them first.
- **Emilia picked (2026-09-28): past the edge first.** At the edge of the beyond page (once every
  beyond place is open, or via a rumour), send pets by shelf; they never come back, the next page
  fills with their scribbles (no outline, a number to go), full = the page opens (~1-2 h of that
  stage's pets/sec, e.g. 500 for next door, then x50-100 a page). Any pet counts the same. The UI
  word is NOT "scouting" (A3 has it). Look A, the tucked page: the beyond map's torn right edge
  with a signpost spot called **"the edge"**, the next page tucked under it filling with crayon
  scribbles in the pets' colours, "N to go"; side card lists shelves, 1/10/100/all.
- **Then the little school** as the steady drain: classes of spare pets stay on as teachers,
  **every worker (machines too)** gets a bit quicker for good (log-curve class sizes 40, 100, 220,
  450, 900...; the class's rarity mix sets the step; classes multiply). Look A, the classroom: a
  "school" button next to your pet | workers | whistle, a chalkboard "class 4 +3.2%", 24 desks
  filling, finished classes in a "teachers" row. **The sorting rule can send pets to school; you
  ring the bell yourself** when a class is full.
- **Huge parties can't go down the well line** before dungeons (meadow, pond and other risky places
  only). Settling places is dropped. **Stars: only pets that leave or are lost** add a star;
  teachers stay on, so they don't (merge fix for the edge lane).

### C3. A place for "bad" pets  (BUILT + VERIFIED, merged; herd + new homes save v28)
- **Emilia (2026-09-28):** early on they're **put to work** (workers, party fodder), later they
  **feed the sacrifice machine**. But once packs open per second, bad pets become obsolete and
  pile up: they need a way to clear, e.g. **auto sacrifice**.
- **Picked, in order:**
  1. **Busy paws:** new pets go straight to work: each job gets a "new pets join here" switch
     (grows out of jobs_auto / share out and "fill up" on worker spots). Nobody is lost.
  2. **New homes:** a stand on the pets tab takes pets by the shelf (1, 10, 100, all) and **pays
     in boxes** (e.g. 25 commons or 5 rares = a starter box; always less than one pet per pet, or
     it becomes a box engine and kills the piggy bank / B1 restock irritant). Your pet cheers
     ("they'll have a big garden!"), the words never change.
  3. **Feed the machine** (after F1): spare pets are the fuel for the sacrifice machine's spins.
- **The herd** (under C1's shelves): plain pets fold into a **count per rarity x finish**
  ("common 48,210"), so millions fit in the save (a full pet is ~284 bytes) and the tab. **Always
  a card:** favourites, the active pet, holo or better, a pet with a part new to the book, pets
  with F2 upgrades; each shelf also keeps its last ~20 as cards (no re-roll cheat). Jobs, crews and
  parties draw from the counts. Big technical change (Collection, crews/workers as uid lists,
  save migration, night sky placement from an index instead of the uid).
- **The irritant: a room cap + the sorting rule.** Shelves hold ~500 plain pets; past that box
  tables stop and boxes wait in the pile (nothing lost). Clear by hand at first; after enough
  clearing a **sorting rule card** turns up ("new pets below rare go to work / new homes / the
  machine", keeps: new parts, holo+, favourites always; off by default; only touches pets pulled
  after you switch it on, so every loss is chosen; a "sorted today" number on the shelf).
- **Night sky:** **every pet that leaves** (new homes, fed) adds a star, never explained.
- **Prep:** the stand's and the rule card's look (mockups), the exact cap and box payback numbers.
- **Emilia picked (2026-09-28):** look A, the stall (stand in the side column: tap a shelf, take
  1/10/100/all; box jar + starter box pile under it; the rule as a tilted index card). The stand
  pays **points toward a sunny box** (common 1, uncommon 2, rare 5, epic 12, legendary 20; 25
  points = a box). **Any rarity can go to new homes, by hand AND by the rule.** The rule's keeps: a
  **finish stepper** ("<holo> and up"), new parts and favourites always kept.
- **The herd built (with C1, lane c1-c3):** counts per rarity x finish, always-cards, errands /
  workers / parties / the whistle / the kitchen from counts (stand-ins for adventures), the night
  sky by index, the room cap (one cap, coins, simple first version; a box counts as its most pets).
- **Built 2026-09-29 (lane c1-c3, notes in docs/plans/C3-done.md):** busy paws ("new pets join
  here" per shared-out errand, in the shoebox, and per workers' job on its side card; replaces
  jobs_auto), the new homes stall (look A: side column, tap a plank to pick, 1/10/100/all, points
  toward a box 1/2/5/12/20/40 per 25, jar + pile, "they'll have a big garden!"), stars for every pet
  that leaves, the sorting rule card (after 300 by hand; below / go to new homes or work / keep a
  finish and up, new parts and favourites always; off by default; box openings only; "sorted
  today"). Save v28 (herd + new homes in one bump at the merge). Still to do: feed the machine
  (F1, lane plushie), room upgrades (lane house). The pace sim staffs errands from resting cards and
  up to 10 stand-ins a count (roughly right for the herd).

---

## Phase D: late-mid, parts and grafting become the "woah"

### D1. Parts with modifiers  (BUILT, merged, no save change)
- Parts are a late feature already (40 trips). **Emilia:** changing your pet should be a "woah"
  moment once you know how pets roll; every part has modifiers.
- **Decided:** a part's modifier is **a named knack** (lucky paws: +luck, big ears: spots places...)
  whose size scales with rarity; your active pet's knacks boost everything.
- **Prep:** the knack list per slot, how it's shown.
- **Emilia picked (2026-09-28):** look C, sewn badges (round badges under the pet, tap to read;
  grid cards get their best badge on the corner). **One knack per part** (35, slot themes: body =
  adventures, palette = coins/machine, pattern = finds, eyes = spotting, accessory = helping
  hands). A pet's **finish makes its knacks a little bigger** (e.g. shiny x1.25, holo x1.5).
  **Traits stay** beside knacks (traits per pet, knacks per part). Other pets' knacks help **their
  own trips/jobs a little**. A knack for a system you haven't found yet is **hidden until it
  opens**.
- Grafting (sewing onto your active pet, can fail) exists; the workbench shows it.
- **Built (lane b2-d1, merged, look C):** data/knacks.json (35 knacks, one per part, sizes step x
  rarity x finish), `Knacks` (scripts/pets/knacks.gd), your active pet's knacks are the `knacks`
  boost source, other pets' count a quarter on their own errands, worker jobs and trips (packed as
  `RunState.knacks`), 11 knack-only boost kinds (spots, trip, tough, safe, finds, pickups, treats,
  away, rummage, shiny, pet_boxes). Hidden until parts open and until each kind's system opens;
  power waits for fights (E1). Badges on the pet details (tap to read), the best badge on grid
  cards' corners. Numbers are placeholders. No save change.

---

## Phase E: THE LOOP BREAK

### E1. Combat adventures and dungeons  (DECIDED; the old well BUILDING in lane dungeon, not merged)
- **Emilia:** adventures go from exploration to actual combat; dungeons need ARMIES of good,
  perfectly rolled pets; this is where the player gets clues they're a dictator managing an army
  "for their own good". Swarms follow standing policies (PolicyChooser, rules still to come).
- **Decided 2026-09-28:** a fight is **army power vs the dungeon**: your army's total power (stats,
  rarity, knacks) against each floor's strength; you set policies (push on, retreat at X%
  losses); losses are the cost. Dungeons give **rare parts** (the best only come from dungeons),
  **the next layer's key** (clearing opens new mechanics) and **the darker currency**.
  **Dungeons scale forever:** the first floors unlock things, but you can always go deeper into
  any dungeon, and there will be more dungeons, to farm better gear and drops while difficulty
  scales.
- **Decided 2026-09-28 (brainstorms):** dungeons pay the darker currency as **lanterns** (see
  F2); **gear (A2) doesn't work in dungeons**.
- **Prep:** the first dungeon (floors, what it asks for), the policies UI.
- **Emilia picked (2026-09-28): the old well, all the way down.** Bands: the well (floors 1-10,
  rope floors where only the front row climbs), the cellar (11-20, doors, tiny doors only rare+ fit
  through, knock-back doors test luck), further down (21+, stairs forever, a guard every 10th). The
  top of the well stays a trip (the whistle is found there); cellar/below become bands already
  reached, never removed from old saves. Opens with a find at the well ("the rope goes further
  down", min_party ~100, after the whistle). Floor strength ~100 x 1.2^n, **never shown as a
  number** (feeling words: easy peasy, a stroll, comfy, spooky, tricky, so tough, brr!). **Front
  row + tiny doors:** your best ~20 card pets fight, the herd walks behind as reserves. The
  entrance fits 300 at first (widening = the first lantern buy; bounds "sent" for lanterns). Floor
  10 = the first dungeon part + your pet learns "lead the army"; floor 20 = the key to E3 (stays
  fully hidden until found). **Orders: the orders card** (sentences with steppers like the sorting
  rule: "go down to floor ‹10›", "come home when ‹30%› are gone", more lines earned per floor
  kind, e.g. "who goes first: plain ones / anyone / the front row"). A third page in adventures
  (adventures | upgrades | dungeon). Needs C3's herd first.
- **Look A, the cross-section:** the well as a tall scrolling column (rope floors 1-10, cellar
  11-20 with tiny doors on 13/17 and knock-back doors on 15/19, stairs further down with a guard
  every 10th); the army in the middle (front row of 20 card pets in a 7-wide grid with your pet's
  flag, the herd mound + shelf steppers, entrance meter 282 / 300); side column: the orders card +
  a "last time" card.
- **The perk tree lives on the well wall** (picked 2026-09-29, look A, on the walls): coral things
  (woolly scarf, nightlight, dinner bell, lunchbox, pinwheel, music box, paper star, lucky coin,
  rattle) hang on nails down the left soil lane joined by a coral thread (solid down to the last
  bought, dashed chalk after); the bow on the roof post = the widened entrance (the first buy).
  **A chain**, each thing needs the one above; **2 endless tips** (coins, pets/sec, +3-5% a level at
  x3 the price) open once the chain is done. Unbought things are dashed outlines; nails below the
  deepest floor reached stay fully hidden. Plushie perks hang there too, hidden until the machine
  opens. BUILDING with E3 in lane sewing.
- **Held landings** (F3): crowds hold well landings 10/20/30 (crowds + count pills on the
  landings), armies can start from the deepest held one (skipped floors pay no lanterns).

### E2. The next map page (zone 3) and the invasion lore  (DECIDED; BUILDING in lane nextdoor, not merged)
- **Emilia:** you conquer the backyard, then intel opens places beyond; the real lore is invading
  and expanding your territory. **Prep:** zone 3's places, how its intel comes.
- **Emilia picked (2026-09-28): zone 3 is "next door"**: a row of back gardens at night, recoloured
  backyard doodles with little lit windows that go dark one visit at a time. **Opens by pets past
  the edge** (C2), so next door + the midnight box arrive in stage 3. **Places become "ours" after
  enough visits, the backyard too** (the pet colours the doodle in, safer, pays a bit more, locals
  stop turning up; high N for the backyard). Locals only ever as traces.
- **Look A, the street:** a row of house backs along the top, their windows are the lights, one
  goes dark per visit; when the last goes out the garden is coloured in (in your pet's own colour:
  lilac blob = lilac) and a flag goes on the roof; picket fences between gardens, one path in
  through their gate. Places: their gate, garden path, greenhouse, pond, porch (broken capsule
  machine = the midnight globe), doghouse (risky); lights 3/4/5/5/6/8 (placeholders); the gate and
  path start as ours.

### E3. The hard dungeon unlocks sacrificing  (DECIDED; BUILDING in lane sewing, not merged)
- **Emilia picked (2026-09-29): the sewing room**: a side door on well floor 20 (tap it and the
  cross-section pans sideways); ~8-10 rooms (button tin, pin cushion, thread maze, ribbon drawer,
  the big scissors), each with a strength (E1's army maths) AND a chalk-drawn lock: part pictures
  for named D1 knacks (halos, bunny ears, horns), trait icons, finish swatches, rarity colours;
  each drawing fills in as a front-row pet matches it (no text); tapping an unfilled mark shows
  where it comes from (like bit_hint). No holders line. The first clear teaches the sorting rule
  **keep lines, capped** (each keeps the last ~50 matching pets as cards). **The last room gives a
  working plushie machine and sews one free button onto your active pet.** After F1, rolled rooms
  farm forever with **button locks** (same lanterns as the well).

---

## Phase F: mid game, a new layer on pets

### F1. The sacrifice machine: upgrading parts  (DECIDED; BUILDING in lane plushie, not merged)
- **Emilia:** old perfect pets go into a machine; the better the pet, the more likely one of its
  parts gets upgraded; probably a slot machine UI. Pitched: the reels are the pet's parts, where
  they stop picks the part; a better pet gives an extra reel or a nudge.
- **Picked: the "stuffed toys" bundle** (plushie logic: a miss just "lets out some stuffing",
  your pet cheers every spin; what you really do is feed pets to a machine to upgrade one
  favourite, and the game never says so). The machine runs F2's reels, see below.
- **Prep:** mockup 2-3 looks; the upgrade's name (see F2).
- **Emilia picked (2026-09-28):** look A, the cabinet (pink toy slot machine, hopper funnel on top,
  5 reels, a lever). The machine is **the plushie machine**, a page in the workbench (toys |
  plushie machine). The part upgrade is called **buttons** (plushie button eyes, sewn on one by
  one). An upgrade you didn't hold **auto-banks** on the next spin; anything held when the spins run
  out is banked too. Stuffing's extra reel is **a wild 6th reel** (its button goes to the part you
  pick). It opens from E3's last room (a working plushie machine + one free button on your active
  pet).

### F2. A new layer on pets: perfect is hard again  (DECIDED 2026-09-28)
- **Emilia:** the mid-game main goal: a new layer so a perfect pet is really, really hard again;
  a new gambling loop more complex than a lever (so pets can't automate it at first); it earns
  something darker than coins (maybe "perk points"), slowly at first, billions later. Old layers
  get abstracted and handed off to pets.
- **The layer: reels (working name "Star Reels").** Each part of a pet gets 0-5 upgrades, and
  they multiply its knack (D1, so D1 comes first). Upgrades stay on the part, so a grafted part
  keeps them (dungeon parts and grafting join the loop). A try: pick the keeper, feed pets in. The
  fed pet's rarity = how many spins, its finish = nudges, its traits tilt the reels. One reel per
  part; each lands on an upgrade, a blank or a crack. **Bank** it (that reel stops) or **hold** for
  a double next spin; a crack takes a held one away. A 5th upgrade is ~1-2% a try; perfect = 5 on
  all 5 parts.
  - **Not called stars:** "star" stays the night sky's word. Name picked later (pips, sparkles,
    stitches...).
  - **Per pet** (a deep chase), not per part kind.
  - **Shows odds**, like boxes and the workbench sacrifice (it's a machine).
  - **A failed try costs only the fed pets and held upgrades.** The keeper is always safe.
  - **Handoff:** later you give pets rules (bank at 3, never risk the body) and they play worse
    than you.
  - One layer now; a second whole-pet axis can come much later (ideas in docs/brainstorms.md).
- **Picked since:** the upgrade is **buttons** (F1). **The darker currency is ONE currency called
  "wisps"**, colour **candy floss coral**, with two sources: lanterns (dungeon floors) and stuffing
  (plushie machine misses) are both wisps. Its perk tree hangs on the well wall (E1).
- **The darker currency (the two sources, first written as lanterns and stuffing):**
  - **Lanterns:** dungeon floors (E1), the base source and the first trickle. A cleared floor pays
    base x ~1.15^floor x pets SENT (never pets lost); the lit dungeon map is the progress bar.
  - **Stuffing:** each spin that misses puffs stuffing by rarity (common 1 ... mythic 10k) x
    perfection; stuffing buys nudges, holds and an extra reel, so misses feed the next hit.
  - **Never pays for a lost pet**, only for pets sent or spent on purpose.
  - **Spent on both:** gambles (spins, nudges, holds, banners) and a small perk tree you keep.
  - **May buy multipliers** on coins, xp and pets/sec (so old prices keep scaling), but never turns
    back into coins, and nothing with a coin/xp price costs it.
  - Needs a new colour key in all 5 themes (not lilac, not the epic tier colour).
- **The loop:** pets/sec → spares go to work, then new homes → dungeons pay lanterns → the hard
  dungeon opens the machine → the sorting rule feeds spares into the hopper → spins upgrade the
  keeper's parts (knack x upgrades), misses give stuffing → stuffing buys better spins → an
  upgraded army goes deeper → more lanterns, and you want more pets/sec again. Manual: bank or hold
  on every reel. Irritant: "one more on the eyes".
- **Watch out:** only ONE thing may hand out parts from pets (parts flood, see the scrapyard
  note): the machine gives stuffing, not parts back.

### F3. Pets as currency, spent everywhere  (DECIDED; wish jar + shed workshop BUILDING in lanes wish, workshop)
- **Emilia:** pets are a stepping stone: spent on automation, dungeons, adventures, scouting,
  tech, science, to earn the real currency that moves you on.
- **Emilia picked (2026-09-29): the wish list, then the shed workshop, then held landings** (no
  pillow). Past the edge and the school (C2) come first.
- **The wish list, look A, the wishing jar:** pin one look you've seen in the book; a jar sticker
  in a side column beside a narrower book spread, the wished sticker as the label, pets fill it
  with dots in their colours, 4 bands (steps 200 / 600 / 2k / 6k, 8,800 in all), a gold star per
  full step, the lid glows when done; "N / M", shelf chips, 1/10/100/all. **Every pet counts 1**,
  no finishes, it ends after 4 steps, switching the wish keeps the old one's filled steps. Each
  full step raises that look's weight inside its already-rolled tier; **it steers every box** (your
  rips, your pet's, the box tables); rarity never moves.
- **The shed workshop, look A, the card on the map:** once the old shed is ours and the whistle is
  found, tapping the shed sticks a workshop card on the backyard map: 3 drawings pinned on a plank
  with progress bars, the picked one's needs as helpers + rarity bars, 1/10/100/all, "not yet" /
  "build it!"; built things stand around the backyard. Drawings are built by crowds of pets with a
  rarity need, **pets only** (no wisps), each takes away an old chore. **All 3 pinned drawings
  fill at once; you tap "build it!".** Chores that are manual on purpose stay manual (the weather
  vane only answers plain trip choices; the school bell and reel banking stay yours). The 8
  drawings from the mockup table to start (tune later).
- **Held landings:** see E1. Stars only for pets that leave or are lost (helpers and holders stay).

---

## Phase G: shipping

- Care / the desktop pet (buffs and check-in rewards), sound pass, real art, the Windows build
  (WindowSource backend), Steam page and rating (target PEGI 7-12; loot-box law notes in
  docs/design.md).
- **Care, picked 2026-09-29: A, then E, then C** (BUILDING in lane care, not merged).
  A: care becomes buffs: food and mood **freeze while the game is closed**; the kitchen keeps food
  up to 70; above 70 = full tummy coins x1.2, happy luck x1.1 (through the B2 boosts, on the
  receipt); an empty bowl is just no bonus, never a sad pet; **snacks cost capsules**; the old
  coin trickle goes; design.md's "+50% for 2 h" changes. E: quiet paws: out on your windows your
  pet keeps doing its one job with **poses only, no text** (opens a box on a window edge, holds up
  a good pull 4 s, taps its foot when an adventure waits); setting **off / big things /
  everything** (not a second box-opening switch). C: presents: one every 3 h of wall clock, a
  pocket of 3, from when the boxes tab opens; **boxes of your newest tier + sometimes a toy
  capsule, never bits, never a pet**; out on your windows your pet digs the present up and wears it
  until you tap it.

---

## Cross-cutting (do when a step needs it)

- **X1. Navigation space:** the spine fits about 8 tabs + settings; it's full now (automation made
  it 8). The next tab (gear) needs a plan: group tabs, a second column, or tabs that live inside
  others (e.g. gear inside adventures). **Done for A2:** gear lives inside adventures (adventures |
  upgrades), no new tab.
- **X2. GameState is big (~4000 lines now):** split into parts (machine, errands, automation, runs)
  when a step touches it anyway.
- **X3. Tuning numbers in data/**, not code (some still in game_state.gd).
- **X4. Tests:** done. `tests/test_core.gd` now tests GameState itself in a test profile
  (`_test_game_state`, run with `-- --profile=core-test-<lane>`): save migrations v14..now plus a
  round trip, crank catch-up with and without the stool, the auto-adventure loop, thousands of
  workers with time limits, gear (A2) and the jar, kitchen and scouting (A3). It found that sending
  hundreds of auto parties was slow with many pets, and that is fixed. Checks line:
  `godot --headless -s tests/test_core.gd -- --profile=core-test-main` in the main checkout (the
  name `test` is refused; `DESK_PETS_SLOW=3` stretches the time limits when lanes run at once).
- **PRICES (done):** errand tools and boxes priced in capsules (errands.json tool "capsules",
  boxes.json "capsules", x Machine.coin_value via Jobs.tool_cost / GameState.box_price). Early
  prices unchanged (tools match the old coins at a capsule worth 75, boxes at 1); later they keep
  up with the pay. Your pet's box reserve is in capsules too (boxes.json "reserve", save v25
  reserve_capsules). Flow: prices. Questions for Emilia in docs/plans/PRICES-done.md.
- **Small picks (done, lane b1):** the pet's possessive slips cut (unlocks beyond line, voice
  trail_part_kept, the scaredy rumour); the capsule machine shows its odds (a "prizes" tag in the
  stage corner flips into the odds card, Machine.odds / GameState.machine_odds with every boost the
  roll uses, flow machine_odds); fever stays a burst (machine.json fever_burst 0.8 of the relight
  time caps it, base 8 s, +1 s a level of longer fever, 11 s max; counts in pulls). See
  docs/plans/SMALL-done.md.

---

## Still to do around the merge (2026-09-29)

- Merge the lanes that are built but not merged yet (see "Lanes" at the top), renumbering their
  save bumps from v29 on, then re-run every flow and the tests on the merged game.
- Apply the A1 balance picks that aren't in yet (errands tweak "C", crank 48 -> 15, automation
  prices ~x100, auto_adventures 60 -> 30, pond spot 0.6) and re-run the pace sim.
- Tool scripts (-s) must never save: GameState `_can_save = false` when a tool script is the main
  loop (today only `GameState.testing` turns saving off).
- Old rule breaks seen in screenshots: '???' placeholders are still in the spine's locked tab, the
  collectibles toys switch (collection_tab.gd), the errands pegboard's closed tools
  (errand_tools_view.gd), the machine tree's detail card and secret toys; the errands board's "?"
  card and hint text under the errands title; map lead labels cut off at the edges ("gears out
  this way?", "bolts out this w"), "the garden path" label under the speech bubble; the errands
  header ellipsis.
- Flows with big `pets` / `herd` steps need `stickers off` after `view full`, or A4's sticker
  popup covers every later shot (pets_shelves and new_homes were fixed in the merge).

## Open questions from the lanes (ask Emilia)

Every lane's full list is in docs/plans/<STEP>-done.md ("Questions for Emilia"); the short ones
are collected at the end of docs/picks.md. The bigger ones:
- A1: should errands out-earn the lever (picked: 1-3x), how much your pet's crank matters, is 4 h
  the early game (toys left out of the sim)?
- A2: the leaf only saves from "hurt", not "lost"; the harness shows at the wheelbarrow.
- A3: a floor on the kitchen's bonus at huge crews? A4: several full pages at once queue their
  popups one by one (or one popup?).
- B1: old lucky boxes became sunset boxes 1:1; the midnight looks (dragon is the only legendary
  body) can't be pulled until next door; with the piggy bank your pet buys the cheapest
  switched-on tier (or the best it can afford?); only the cellar and further down bring sunset
  boxes (every beyond place?).
- B2: should automation speed also speed automated adventures? Should gear count on the receipt?
- B3: the whistle at 30 workers, caps (backyard 60 / 20, beyond 600 / 200) also stop buying by
  hand, set aside starts at 250k, hauls go to the cheapest next spot.
- C1: holo+ are always cards (~150k cards after a million pulls: only holo+ with something extra?);
  room numbers (500, x1.5, 500 coins x1.8); herd pets work at average stats with no traits.
- C3: errand join switches live in the shoebox; the rule's "below" tops out at mythic (add "any
  rarity"?); a million commons pay 40,000 boxes at once (shrink points as the herd grows?).
- D1: knacks open with parts (40 trips; earlier?); the crown says "automation" (keep "workers"?);
  "while away" makes time away count more rather than raising the cap.
- PRICES: the box reserve shows as coins (or "keep N boxes"?); a starter box = 50 capsules when
  the shop opens (5k-10M coins: too steep?).
- X4: the welcome-back payout multiplies one lucky capsule thousands of times (roll more, or scale
  only plain coins?).

## Suggested order

Merge the waiting lanes (A5 sunset globe, C2 edge + school, E2 next door, E1 the
well, care, room house, E3 sewing room + perk wall, F1 plushie machine, F3 wish jar + shed
workshop) → the balance picks + a new pace run → the rule-break cleanup → A5's midnight globe
(needs E2) → F2's handoff rules → X2 (split GameState).

Each step's **Prep** can be done ahead: answering its questions or picking its mockup look makes
it ready, so a long unattended run can build ready steps back to back.
