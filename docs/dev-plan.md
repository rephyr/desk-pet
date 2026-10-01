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
- **On test (2026-09-29, wave A):** A2 gear, A3 more errand jobs, A4 book rewards, X4 tests, A1
  pace sim, PRICES, B2 boost plumbing + D1 knacks, B1 box tiers + the small picks, B3 the whistle,
  C1 the bookcase + the herd, C3 new homes (save v28).
- **On test too (2026-09-29, wave B, merge verify passed, pushed from lanes/merge):** B2
  the receipt, care A/E/C (presents save v29), A5 the sunset globe (v30), E2 next door (v31), C2
  past the edge + the little school (v32), E1 the old well (v33), F1/F2 the plushie machine (v34),
  E3 the sewing room (v35), the wisps perk wall (v36), held landings (v37), the wishing jar (v38),
  the shed workshop (v39), the room house card (v40), the round 3 mockups; then the A1 balance
  picks, a pace re-run, the rule-break cleanup, Emilia's answers after the merge and the balance
  fixes from the third pace run (see "Still to do around the merge").
- Tools: tests/test_core.gd, tools/play.py flows, tools/balance.gd, tools/pace.gd (A1),
  tools/machine_pace.gd.

**Lanes (2026-09-29):** steps are built in parallel in git worktrees under
~/projects/desk-pets-lanes/ (branches `lanes/<name>`), each writes docs/plans/<STEP>-done.md,
and `lanes/merge` merges them one by one (save versions renumbered in merge order). play.py takes
`DESK_PETS_LANE=<lane>` so each lane plays in its own test profile and Xvfb display. **Every lane
is merged now; nothing is building.**

Known small open items: the "new: the bag!" popup can land on the trip postcard; balance note (a
huge scrapyard crew floods the bag); the welcome-back payout scales 200 rolled capsules up to
every pull (one lucky golden can be multiplied thousands of times). (The sunny tree's overlapping
node labels are fixed: names wrap to their room.)

---

## Playtest 1 (2026-10-01): Emilia played start to end with dev tools

What she found, and what we're doing about it, in order (P1 first).

- **P1 lag** (BUILT 2026-10-01): a late save hitched ~150 ms every second. Fixed: the pet's
  crank works its odds/boosts out once a batch and tells toys/unlocks once (not per capsule);
  automation's saves wait for the 30 s autosave; the night sky paints into a picture and only adds
  new stars; window reads go through Hyprland's socket (hyprctl was ~5 ms a call); hidden pet
  pictures stop animating; the tutorial ring stops redrawing when gone; the bookcase only rebuilds
  planks whose look changed (numbers update in place); the errands board catches up on pets
  coming and going every 3 s. Still to do: toys/workbench rebuild per tick (part of P2), a tab's
  first build (collection ~100 ms headless).
- **P2 toys + workbench broken**: the "playing" row never wraps (every max-level edition is a
  favourite: up to 48 slots) and stretches the toys page past the window; huge cards; raw numbers
  (x288000). Spare toys past max level are dead. Workbench toy bench: one strip of 48 chips, no
  bulk actions, 2 of 3 benches empty late. **Decided:** spare toys feed into a sink (which one: to
  design). Toys page layout FIXED 2026-10-01 (favourites folded into one "48 favourites, always
  on" spot, "3 free spots", cards keep their size, 72k-style numbers, rebuilds every 3 s from
  background changes; flow toys_late). Workbench mockup: design/mockups/screens/workbench-toys.html
  (one row per toy, bench per toy, bulk risk x1/x10/all; sink ?look=A toy chest for workers,
  B shine past max with stars, C stuffing for the plushie machine). **Emilia picked B.** BUILT
  2026-10-01: ToyBench = a row per toy (finish dots, "ready!" tag, count) | the picked toy's
  edition cards (combine as far as the spares go, fix), sacrifice x1 / x10 / all with a tally,
  and for a favourite "shine it up": star n costs shine.first x shine.x^(n-1) spares (10, 100,
  1000...), each star counts like shine.levels more levels (data/toys.json "shine", Toys.stars /
  shine / combine_all / sacrifice_many, save v42 field owned[ed].stars). Flow toys_late.
- **P3 unlocks are luck / invisible**: beyond the fence opens ~80 min before anything there pays
  (far fields gives no bits); automation needs an unpointed return to the fields; cart and hay
  wagon are random finds; whistle/rope need well trips with nothing to see; hidden counters (200
  packs by hand, 40 trips, 500 packs, 300 pets to homes, pets sent). Midnight globe is unreachable
  (porch_machine has no event). Early bits come only from solo backyard trips (~1 per trip), so
  the lever waits on bits; nothing teaches sending several parties; guidance ends after the first
  trip. **Decided (overrides Hidden Until Earned for unlock triggers):** show the next unlocks as
  goal + progress with the reward named, e.g. "rope: 37 / 100 pets sent -> the dungeon". Still no
  copy explaining how a mechanic works.
  BUILT 2026-10-01: Goals (scripts/core/goals.gd: a goal per unlock in reach, steps with progress,
  "goal" names in unlocks.json), GoalsNote "next up" on the home wall (closest 3, tap = its tab),
  "→ errands  0/3" tags on place cards, finds turn up for sure on the 3rd trip that could meet them
  (adventures.json find_sure_by, GameState.find_tries, save v43), far fields bring bolts + springs
  and the orchard gears + glass (beyond the fence pays right away), your pet asks for another
  party when others are home (voice send_more, every 5 min at most), gold dots on machine /
  adventures / errands / automation for a new affordable upgrade (GameState.buyable /
  upgrade_news / saw_upgrades). DESIGN.md: the Carrot Rule. Flow goals. Pace (steady, 5 runs):
  lights 73 -> 60 min, better drops 113 -> 104, automation 124 -> 115; new glass still waits
  ~27 min on 1 glass (few pets early). NOT done: the midnight globe (porch_machine find + its
  nodes porch_dust / porch_hatch don't exist yet: content to build).
  Then (same day): the backyard's own bit is sure on a finished trip (chance 1.0, was 0.6-0.8),
  and the pace sim learned `--parties=many` (every spare pet out, each party somewhere else). The
  real early bottleneck was one party at a time (the sim, and players nobody told). Many parties,
  5 runs: new glass 14.5 min, lights 38, better drops 64, automation 72; but trips-gated unlocks
  jump ahead (parts at 40 trips lands at 48 min, before better drops): retune those for the
  200 h curve. **Emilia's target (2026-10-01): ~200 hours of game before any prestige layer**
  (time the game is open; stretch existing content first, then add content; back-loaded split:
  machine + backyard ~3 h, coins/packs ~15 h, managing pets ~40 h, loop break ~60 h, late ~80 h).
  No new sims (tight schedule): tune by reasoning, Emilia playtests.
- **P4 late-game redesigns** (plushie stakes BUILT 2026-10-01, see F2; flow plushie_stakes; the
  dungeon page and the perk wall BUILT 2026-10-01, lane dunperks, see below;
  watch: perks now cost real well wisps, the chain was ~460k). **The sewing room BUILT 2026-10-01
  (lane sewing2, look A, the seats):** `SewingPage`, its own page in the dungeon's place (the door
  on floor 20 opens it, "‹ the old well" goes back, wisps chip); room strip (pennants, the next one
  picked, a dashed carrot after it, nothing further); the room's card with "→ next room", a
  feeling word and a seat per mark; tap a seat, then a pet (fitting ones first and lit, the rest
  dim; "where from? ›" for the hint); any card can sit, your active pet and the plushie keeper too
  (both always come home), one pet fills every seat it fits; the army walks in behind ("and N
  more"); the 60 s run with a clock and tiny pets; the result (wisps, came home, again / next room
  ›). Seats are not saved (no save bump). The well page's old slide-in pane (`SewingRoom`) isn't
  reachable now: delete it with the dungeon page redo. Flow sewing. **Emilia's picks (2026-10-01), all
  look A:** dungeon-redo.html A (slim well column + desk: fill up / all / pip slider per shelf,
  orders as choice rows, floor log during the run, came-home report); perks-redo.html A (the well
  wall sheet from the wisps pill, strict chain kept, the nails lane on the well goes); sewing-redo.html
  A (room strip, seats: tap a mark then a pet that fits); parts-redo.html A (knacks on every part
  tile, before/after on the sewing table) + **every card pet gets its FULL knacks on its own work**
  (was 1/4; herd pets still none). Defaults Claude picked (change if wrong): cleared floors walk
  4x faster, new ones 20 s; "fill up" takes the plainest first; lost front-row pets show as faded
  faces, no names; no coming home early mid-run; best bit = a first find, else deepest yet, else
  most wisps; any pet you seat counts for a mark (not only the 20 strongest), your active pet and the
  plushie keeper may go in, one pet can fill two marks; bag tiles show the short "+40% automation". the plushie machine has no stake (sewn buttons are safe, misses pay
  wisps, cracks pay double; one mythic ≈ the whole wisps economy). **Decided:** cracks can pop
  sewn buttons, misses pay nothing, each next button needs better fed pets, holding stakes
  buttons. Dungeon: 10-pet steppers (~480 clicks), 20 s/floor waits, strength never shown,
  thin result card. Perk wall: tiny nails down a 40 px lane, one card at a time, hides the last
  run. Sewing room: crammed into the 236 px well column, marks only count the 20 strongest, the
  keeper/active pet can't count. Parts: knacks are real but only your active pet gets them fully,
  herd pets get nothing, and the sewing table even says "no change". All need mockups + picks.
  **Parts BUILT 2026-10-01 (lane parts2, no save change):** data/knacks.json `own` 0.25 -> 1.0
  (every card pet's own errands, worker speed, army power and trips get its knacks in full; herd
  pets none; your active pet still feeds the global boost). Workbench "your pet" page look A:
  part tiles with the knack's doodle, its size on your active pet (finish + buttons, `Knacks.row`)
  and a short kind word (knacks.json `short`), the sewing table's now -> after with the leaving
  knack struck out and the new one, the "mood" line gone, "<pet>'s knacks" chips under the bag.
  The boxes row left the page (the home pile and the boxes tab have them). The page only rebuilds
  when the bag, your pet or the knack gates change (checked at most once a second). Dev step
  `dice <seed>`; flow parts.
  **Dungeon + perks BUILT (2026-10-01, lane dunperks, no save bump):** the dungeon page look A (slim
  well column, tap a floor to move the flag; the army card with fill up / empty, the entrance by shelf,
  the front row 11 wide, a 10-pip slider + all per shelf; orders as rows of choices, the target the
  one stepper; the run card: floor N of M, walking bar, walking / bumped / stayed below / wisps so far,
  the front row's faces, a log row per floor as it happens; the came home report: 4 numbers, faces
  faded / plastered, by shelf, floor by floor, best bit, same again! / change the army). Cleared floors
  walk 4x faster (dungeon.json cleared_x, runs keep `known`); fill up takes the plainest shelf first,
  never the front row. The perk wall look A: the "perks" button by the wisps (gold dot: one you can
  afford) opens the well wall sheet (WellWall + PerkTag), the nails lane is gone. Flows dungeon,
  perks, held, sewing. Still open: the report isn't saved (a restart shows "last time" only).

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
  30; garden -> pond spot 0.3 -> 0.6. **Applied on lanes/merge (2026-09-29)**, plus the kitchen
  tuned to `most` 0.5 / `half` 1.
- **Re-run on the merged game (docs/reports/pace.md, save v40):** before boxes errands sit at
  0.4-1.5x the lever (a bit under the 1-3x target: capsule prices and tweak C stack); after better
  drops errands earn 100-300x (crews of 500 at crew^0.8, only the room stops the flood); automation
  is still bought the minute it opens (crank 1-2% of the lever as picked, workers 0.5-1%); scouting
  never opens in 4 h and the jar is late (81 min); bits stay the only tree gate; casual players
  reach new glass at ~3.5 h. Suggested (not applied): crew_power 0.8 -> 0.6 or starter box 500
  capsules, lemons / bigger_jar grow 1.3, scouting at jar lv 5, new glass 1 glass, teach the sim
  to buy room steps. Emilia's questions are at the end of the report.
- **Balance fixes applied (2026-09-29, docs/reports/pace.md, third run):** errands crew_power 0.2,
  base pay 20 / 12, smaller goals and tips, the jar reworked (scouting ~78 min steady), new glass
  1 glass, automation prices x5, room steps ~a sunny box per new bed (12500 / 17500 / 30000 /
  40000 capsules), pat cooldown 300 s. Errands now 0.6-3.2x the lever all game; casual new glass
  ~98 min. The sim buys room steps, pats on its clock, and its parties no longer know where finds are.
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

### A5. The machine later: a globe per map page  (sunset globe BUILT + VERIFIED 2026-09-29, lane globes, merged as save v30)
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
- **Built (lane globes, merged as save v30, notes in docs/plans/A5-done.md):** look A. Globes +
  bits in data/machine_tree.json; the sunset globe comes home from the far fields after the tiny
  machine (event `fields_sunset_globe`), broken, beside the sunny one; 5 repairs off the old hatch
  (nest > cork > pulley > amber > hatch) with corks + amber glass (orchard), pulleys (old well),
  copper wire (far fields), only once it's home. The newest working globe is the hand; your pet,
  workers and errands use the one behind. Shared vs own-globe effects (chutes, lights, glass per
  globe), step x12, the hatch = sunset boxes + the sunset toy set (firefly, hedgehog, sleepy owl,
  paper lantern). Fixes list, a sign per globe on the tree. **Midnight is data only** (next door
  is in now, so it can be built next). Flow globes. Open: dim named fixes vs the "no ???" rule,
  which bits the pills show, repair prices vs bits as the gate.
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

### C1. The pets tab as containers  (BUILT + VERIFIED, merged; the herd is save v28, the house card v40)
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
  pet counts toward the room, pets on jobs too.** BUILT (lane house, notes in
  docs/plans/HOUSE-done.md), merged as save v40: 4 coin steps (capsules x coin value), then wisp
  squeeze-in steps (hidden until wisps: the dungeon or the plushie machine open), then endless "one
  more squeeze". Coin steps set by the pace sim (2026-09-29): 12500 / 17500 / 30000 / 40000
  capsules, about a sunny box per new bed; the wisp steps are still placeholders. Flow: house.
- **Built 2026-09-28 (lane c1-c3, notes in docs/plans/C1-done.md):** look A, the bookcase: cushion
  (active, favourites, best), a plank per rarity (tag, newest 4, a mound that grows with the count,
  shiny count, the best knack's badge on each card's corner), a shelf opened (herd chips,
  always-cards, newest 20, sticker with heart + make active), the room pill.

### C2. Pets per second  (past the edge + the little school BUILT 2026-09-29, lane edge, merged as save v32)
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
- **Built (lane edge, merged as save v32, notes in docs/plans/C2-done.md):** past the edge (look A,
  the tucked page: the torn beyond map, the signpost "the edge", the next page tucked under it
  filling with scribbles, "N to go", the edge card with shelves and 1/10/100/all; pets never come
  back, a star each; 500 opens next door through `GameState.open_page`) and the little school
  (look A, the classroom: `your pet | workers | whistle | school`, classes 40/100/220/450/900/x2
  fill 24 desks, you ring the bell, every worker x(1 + step) per class). The school is the `school`
  source of `boost("automation")` and `boost("errands")` ("the little school" on the receipt), so
  it also quickens your pet's crank and box opening. The sorting rule can send pets to school.
  "N pets a minute" pill once box workers exist. Flows edge, school.

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
  today"). Save v28 (herd + new homes in one bump at the merge). The pace sim staffs errands from
  resting cards and up to 10 stand-ins a count (roughly right for the herd).
- **Since merged:** feed the machine = the plushie machine's hopper takes herd shelves and card
  pets (F1, v34); room upgrades = the house card (v40); the rule can also send pets to school
  (C2) and keeps "keep lines" from the sewing room (E3). A pet is in one place at a time: the
  stall never takes the army, the plushie keeper or buttoned pets.

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
  boost source, other pets' count a quarter (in full since P4) on their own errands, worker jobs and trips (packed as
  `RunState.knacks`), 11 knack-only boost kinds (spots, trip, tough, safe, finds, pickups, treats,
  away, rummage, shiny, pet_boxes). Hidden until parts open and until each kind's system opens;
  power waits for fights (E1). Badges on the pet details (tap to read), the best badge on grid
  cards' corners. Numbers are placeholders. No save change.

---

## Phase E: THE LOOP BREAK

### E1. Combat adventures and dungeons  (the old well BUILT, merged as save v33; perk wall v36, held landings v37)
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
- **Built (E1, lanes/dungeon, merged as save v33):** the old well dungeon, look A (the cross-section).
  data/dungeon.json, `Dungeon` (rules), `DungeonView` / `WellColumn` / `FrontRow` (the adventures
  tab's third page), save `dungeon` + `wisps`. The well trip caps parties at 100; a party of 100
  finds the rope (`deep_rope`, after the whistle) that opens the dungeon; the cellar and further down
  are bands now (old saves keep them as reached, and they don't count for the edge's "every place
  open"). Army = cards you add (best 20 by power in front, your pet's flag) + herd by shelf,
  entrance 300; floors 100 x 1.2^n as feeling words; orders card (floor, home at X%, who goes first
  from the cellar); losses become stars; wisps per floor for pets sent. Floor 10: an epic part +
  "lead the army" (automation job `army`); floor 20: the tiny key (E3), hidden. Notes and open
  questions in docs/plans/E1-done.md (something that sends 100 pets at once, wisp spending).
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
  opens.
- **Perk wall built (lane sewing, PERKS, merged as save v36):** 12 links on nails down the left
  lane (the bow = the entrance first; little flag, dinner bell, spool, nightlight, lunchbox, woolly
  scarf, pinwheel, music box, paper star; thimble + ribbon hidden until the plushie machine) + 2
  endless tips (the lucky coin, the rattle; x3 a level from 20k) once every link is bought once.
  Boost source `perks` (front, herd_power, cellar, stairs, lanterns, pets); the music box runs the
  army while away. data/perks.json, Perks, PerkNail; `dungeon.entrance` moved into `perks`. Flow
  perks. (P4, 2026-10-01: the nails lane went; the perks hang on the well wall sheet, WellWall.)
- **Held landings** (F3): crowds hold well landings 10/20/30 (crowds + count pills on the
  landings), armies can start from the deepest held one (skipped floors pay no lanterns).
  **Built (lane sewing, HELD, merged as save v37):** every 10th cleared landing is held by a crowd
  sent by shelf (500 / 2k / 8k, then x3; data/dungeon.json hold); the orders start from the
  deepest held one ("start from ‹the top | landing N›"); skipped floors pay no lanterns and take
  no time; a held guard landing has no guard; holders stay on for good with no star. Flow held.
- The rope find (after the whistle) counts every pet ever sent to the well: once ~100 have gone
  down (`after_sent`, data), the next party finds it (answered 2026-09-29). Still open from E1: the
  wall under 0.4 of a floor's strength; the knock-back miss pays nothing.

### E2. The next map page (zone 3) and the invasion lore  (BUILT 2026-09-29, lane nextdoor, merged as save v31)
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
- **Built (lane nextdoor, merged as save v31, notes in docs/plans/E2-done.md):** next door, look A
  (the street): data/unlocks.json page `next_door` (night paper, street layout), 6 places in
  data/adventures.json, places become ours (`Ours`: one light out per visit, then your pet colours
  it in with its own colour + a flag; danger x0.5, loot x1.2, `local` events stop; backyard after
  40 visits once next door is open), `StreetPage` draws it, place card lights row / risky / x1.2.
  Opened by past the edge (C2) through `GameState.open_page("next_door")` (unlock `earn: called`).
  Next door brings midnight boxes and looks. Flow next_door. Not yet: the porch's midnight globe
  (A5), next door adding worker machines/tables to the whistle's caps.

### E3. The hard dungeon unlocks sacrificing  (the sewing room BUILT 2026-09-29, lane sewing, merged as save v35)
- **Emilia picked (2026-09-29): the sewing room**: a side door on well floor 20 (tap it and the
  cross-section pans sideways); ~8-10 rooms (button tin, pin cushion, thread maze, ribbon drawer,
  the big scissors), each with a strength (E1's army maths) AND a chalk-drawn lock: part pictures
  for named D1 knacks (halos, bunny ears, horns), trait icons, finish swatches, rarity colours;
  each drawing fills in as a front-row pet matches it (no text); tapping an unfilled mark shows
  where it comes from (like bit_hint). No holders line. The first clear teaches the sorting rule
  **keep lines, capped** (each keeps the last ~50 matching pets as cards). **The last room gives a
  working plushie machine and sews one free button onto your active pet.** After F1, rolled rooms
  farm forever with **button locks** (same lanterns as the well).
- **Built (lane sewing, merged as save v35, notes in docs/plans/E3-done.md):** a pink door on floor
  20 once the tiny key is found; the column slides to the rooms; 9 fixed rooms with chalk locks
  (part pictures, traits, finishes, tiers, buttons; filled by front-row pets, ticks, a tap = where
  it comes from), each one army fight; keep lines from the tin (+1 at rooms 4 and 7, cap 50); the
  last room opens the plushie machine (F1) and sews a free button; rolled rooms with button locks
  forever. data/sewing.json, Sewing, SewingRoom, ChalkMark, SewDoor; flow sewing. While the room
  shows, your pet leading the army waits at home so a room gets a turn. **Redone in P4** (see
  Playtest 1: SewingPage, seats instead of the front row). Open: exact vs "or better"
  marks, room names past the first five, room floors vs the pace sim.

---

## Phase F: mid game, a new layer on pets

### F1. The sacrifice machine: upgrading parts  (BUILT 2026-09-29, lane plushie, merged as save v34)
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

### F2. A new layer on pets: perfect is hard again  (BUILT 2026-09-29, lane plushie, merged as save v34)
- **Built:** the plushie machine (look A, the cabinet), a workbench page hidden until the sewing
  room's last room gives find:plushie_machine (E3 grants it; one free button on the active pet).
  Keeper ‹ ›, hopper from herd shelves (+) and card pets, 5 reels with odds shown, bank / hold /
  nudge, auto-bank, spins run out -> banked, wild 6th reel, wisps (candy floss coral) from misses
  buy nudges, holds and the wild reel (the same purse as the dungeon's lanterns). Buttons 0-5 per
  part multiply its knack (x1.5 each), stay on grafted parts (slot:id@n), make a pet always a card.
  The keeper stays home (no adventures, no army). data/plushie.json, Plushie, PlushieMachine,
  save v34 (plushie, buttons). Flow: plushie. The plushie perks (thimble, ribbon) are on the well
  wall now. Open: handoff rules (bank at 3...), balance.
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
  - ~~A failed try costs only the fed pets and held upgrades. The keeper is always safe.~~
    **Changed after playtest 1 (2026-10-01):** a crack knocks a sewn button off its part (one
    more if the reel was on hold; a nudge off the crack puts them back), misses puff nothing,
    and each next button needs a better fed pet (data/plushie.json "needs": common, common,
    rare, epic, mythic for the 1st..5th). Wisps now only come from the well and its rooms.
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

### F3. Pets as currency, spent everywhere  (BUILT: the edge + school v32, held landings v37, wish jar v38, shed workshop v39)
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
- **Built (lane wish, merged as save v38, notes in docs/plans/WISH-done.md):** the wishing jar
  (Look A): jar beside a narrower book, earned with box tables (`others: boxes`), steps
  200/600/2k/6k, weights x1.5/x2/x3/x4 inside the tier via `PetRoller.wish`, rarity never moves.
  Merge fix: the jar takes resting pets from the herd like the edge and the school (a chip per
  rarity, plainest finish first; cards never go), not the lane's per-pet "plainest" sort.
- **The shed workshop, look A, the card on the map:** once the old shed is ours and the whistle is
  found, tapping the shed sticks a workshop card on the backyard map: 3 drawings pinned on a plank
  with progress bars, the picked one's needs as helpers + rarity bars, 1/10/100/all, "not yet" /
  "build it!"; built things stand around the backyard. Drawings are built by crowds of pets with a
  rarity need, **pets only** (no wisps), each takes away an old chore. **All 3 pinned drawings
  fill at once; you tap "build it!".** Chores that are manual on purpose stay manual (the weather
  vane only answers plain trip choices; the school bell and reel banking stay yours). The 8
  drawings from the mockup table to start (tune later).
- **Built (lane workshop, merged as save v39, notes in docs/plans/SHOP-done.md):** the workshop
  card on the backyard map (unlock `workshop`: `ours: shed` + the whistle), 8 drawings (bell rope,
  toy shelf, weather vane on plain choices only, chore chart, garden spade, sewing basket, treat
  banner, letterbox), helpers leave with no star. The merge also brought the lane's review fixes:
  `GameState.party_places()` (the whistle's and bought parties never go into dungeons or risky
  places that aren't ours), unlock popups' "show me" hands the tab what the unlock opens.
  Next: tune the needs against the herd at whistle time (pace sim).
- **Held landings:** built, see E1 (save v37). Stars only for pets that leave or are lost
  (teachers, helpers and holders stay).

---

## Phase G: shipping

- Care / the desktop pet (buffs and check-in rewards), sound pass, real art, the Windows build
  (WindowSource backend), Steam page and rating (target PEGI 7-12; loot-box law notes in
  docs/design.md).
- **Care, picked 2026-09-29: A, then E, then C** (all three BUILT in lane care, merged; presents
  are save v29).
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
- **Care A built:** food/mood only drain while the game is open, full tummy (coins x1.2) / happy
  (luck x1.1) above 70 as `care` boost parts (only while open: none on offline catch-up), kitchen
  keeps 70, snacks 3 capsules x coin_value, pats +8 mood once per 300 s (was 30 s; picked from the
  pace sim 2026-09-29, no daily cap), coin trickle removed, new
  games start at 70/70. data/care.json, `Care`, flow care. No save bump.
- **Quiet paws (care E) built:** out on your windows your pet acts out its job with poses only
  (boxes routine on a window edge, tiny crank machine, a good pull held up 4 s, foot tap facing the
  corner panel while an adventure waits). Setting "out on your windows" off / big things /
  everything (settings.json, no save bump). Flow paws.
- **Presents (care C) built:** `Gifts`, one every 3 h of wall clock, pocket of 3, from when the
  boxes tab opens; a box of the newest open tier (`newest_box_id`), 1 in 5 two, 1 in 5 a toy
  capsule too; your pet holds it on the home tab, digs one up on a window edge and wears it until
  you tap it. Save v29 `gifts`. Flow gifts.
- Still in G: sound pass, real art, the Windows build, Steam page and rating.

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

Done on lanes/merge: every lane merged (save v29-v40, renumbered in merge order); the A1 balance
picks applied and the pace sim re-run (docs/reports/pace.md); tool scripts (-s) never load or
save a save; flows with big `pets` / `herd` steps turn stickers off first. Rule-break cleanup:
no '???' tabs, tools, tree nodes or secret toys, no errands hint card, no hint lines on
adventures, the trail, errands, toys, the workbench, the bag, the bit chips or the home notes
(home notes wait for their tabs; the map note says "nothing new spotted"); map labels and place
notes stay on the page and keep clear of the walking tag; the pet says two bits of news one
bubble after the other; machine tree names wrap; the prizes card sits over the tape; the chest
finds no parts before parts are in the game.

Then (2026-09-29 afternoon/evening, all on lanes/merge, merge verify PASSED, pushed to `test`):
- **Emilia's answers** (docs/picks.md "Answers after the merge"): the rope into the dungeon counts
  every pet ever sent to the well (save field `sent`, `after_sent` ~100); errands are hidden until
  earned (no "opens at coin hunt lv 10" waiting notes or "opens" goal lines, the job just turns
  up); the music box's away runs only take floors cleared safely (`away_safe` 2, nobody lost while
  closed); the edge and wishing jar popups lose their "don't come back" lines; the sunset globe's
  later fixes stay dim by name and cost; the plushie keeper stays one place at a time.
- **Balance fixes from the third pace run** (docs/reports/pace.md, A1 above): errands crew_power
  0.8 -> 0.2 (teamwork +0.01), coin hunt pay 5 -> 20 and lemonade 3 -> 12 capsules, goals x1.1 /
  1.1 / 1.2, lemonade tips 1.15-3, fancy cups x1.5, sweeter lemons grow 1.3, kitchen most 0.3, the
  savings jar 350 capsules + crew power 0.05 (bigger jar 105 / 1.3 / +90, wider slot 160), new
  glass 1 glass, automation prices x5, room steps 12500 / 17500 / 30000 / 40000 capsules, pat
  cooldown 300 s. The sim buys room steps, pats on its own clock and no longer knows where finds
  are. Tests and flows follow the new numbers (errand_tools, errand_jobs, house, pets_shelves,
  globes).
- The crowded backyard map: walking tags keep off the edge, each other and the place drawings.
- Old saves: v29-v40 only ever lived in test profiles; Emilia's real save was at v28 before this push.

## Open questions from the lanes (ask Emilia)

Every lane's full list is in docs/plans/<STEP>-done.md ("Questions for Emilia"); the short ones
are collected at the end of docs/picks.md. The bigger ones:
- A1 (third pace run, docs/reports/pace.md "What's still off"): errands dip to ~0.6x the lever
  right after the lights (fever pays the lever only) and sit under 1x for the first 20 minutes
  after the basket; errands creep up with the herd (3.2x at 4 h, a wisp-sized room will pass 3x);
  workers reach ~40% of the lever by 4 h (fine, or dearer spots?); scouting lands anywhere from 43
  to 133 min (78 median); casual trips take 20-25 min, so casual players make ~12 trips in 4 h and
  rarely find the cart (the biggest thing between them and the lights); bits stay the only tree
  gate. Is 4 h the early game (toys, trail pickups and time away aren't in the sim)?
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
  herd pets work at average stats with no traits. (Room steps set by the pace sim, answered 2026-09-29.)
- C3: errand join switches live in the shoebox; the rule's "below" tops out at mythic (add "any
  rarity"?); a million commons pay 40,000 boxes at once (shrink points as the herd grows?).
- D1: knacks open with parts (40 trips; earlier?); the crown says "automation" (keep "workers"?);
  "while away" makes time away count more rather than raising the cap.
- PRICES: the box reserve shows as coins (or "keep N boxes"?); a starter box = 50 capsules when
  the shop opens (5k-10M coins: too steep?).
- X4: the welcome-back payout multiplies one lucky capsule thousands of times (roll more, or scale
  only plain coins?).
- A5: the sunset globe's later fixes show by name and cost (dim) like the mockup (kept, answered
  2026-09-29); bits pills show only the bits open upgrades need (or every bit you own?);
  sunset repair prices are a few pulls each, bits are the real gate (tune prices up?).
- B2 receipt: it folds on a tab switch; a prize draws over the open machine slip and the slip
  stays open after the pull; the tag shows only once coins have a source; should it shrink to fit
  a short list?
- Care: pats +8 mood once per 300 s, no daily cap (answered 2026-09-29); buffs never count for closed time;
  snack = 3 capsules; new games start at 70/70. Quiet paws: default "everything" or "big things";
  it needs ~92 px beside the pet. Presents: first one 3 h after the boxes tab opens; a toy comes
  with a box, not instead.
- E2: two or more trips back share one tag "N parties are back!"; ours trips aren't quicker;
  backyard places become ours after 40 visits only once next door is open; next door adds no
  worker machines/tables to the whistle's caps (should places that became ours add some?).
- C2: a page's need lowered below what a save already sent carries the extra on (or drop it?);
  the school speeds machine, box and errand workers (not worker parties); it opens after 100 pets
  past the edge; the edge popup's "don't come back" line is cut (answered 2026-09-29).
- E1: floor 10's epic
  part waits until parts open (or give it straight away?); a floor below 0.4 of its strength is a
  wall; army picks stay reserved while home.
- F1: buttoned parts can still slip when sewn (buttons lost); the hopper has no take-back; the
  free button goes on the best-knack part; the keeper can go on errands / worker jobs.
- E3: tier and finish marks match exactly (not "or better"); room names past the first five are
  placeholders; while the sewing room shows, your pet leading the army waits (or queue the room?).
- Perks: the tips need every link bought once (and wait for the plushie links); the music box's
  away runs never lose pets (only floors cleared safely, answered 2026-09-29); tips x3 a level from
  20k (too steep?).
- Held landings: holders come off errands and machines like new homes; steppers in need / 20;
  skipped floors take no time; a held guard landing loses its guard in the fight too.
- Wish jar: opens with box tables; weights x1.5/x2/x3/x4; every jar keeps its boost after a
  switch; "no hat" can be wished for; the popup's "don't come back out" line is cut (answered
  2026-09-29: show, don't explain; the night sky's stars say it).
- Shed workshop: the "adventure ›" / "workshop ›" pills; the chore chart = every errand joins;
  the treat banner tosses full treats; letterbox postcards aren't saved; needs (40..5000) may be
  small at whistle time.
- House: coin steps 12500-40000 capsules (answered 2026-09-29); after the attic the room waits
  for wisps (late); endless steps x4 wisps grow very fast;
  "more room" costs 500 capsules x1.8 a level (97M coins on a maxed machine: too steep?).
- Merges: herd counts count no knacks (x1); a sunset box opens with 1 space left (the room can go
  over by a pet or two); parties the game places skip dungeons and risky places that aren't ours.

## Suggested order

(Done 2026-09-29: merge verified and pushed, the errands note hidden, the pace fixes + third run.)
Emilia plays the new pace by hand and answers the open questions above (the A1 "still off" list
first) → A5's midnight globe (next door is in) → F2's handoff rules → X2
(split GameState, ~6000+ lines now) → Phase G (sound, art, Windows build).

Each step's **Prep** can be done ahead: answering its questions or picking its mockup look makes
it ready, so a long unattended run can build ready steps back to back.
