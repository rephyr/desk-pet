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

Built (all on `test`, see CLAUDE.md "Where we left off"):
- **Stage 1, early-early:** tutorial, the capsule machine and its repair tree (bits from
  adventures), backyard + beyond-the-fence map pages, errands with upgrades (the idle coin maker
  and coin sink), capsule toys + the workbench, rummaging, boxes (the pack ritual), pet boxes.
- **Automation layer 1:** your pet does one job (crank its own machine, run adventures, open
  boxes), taught with coins; the workers page (teach the others, bought spots, you assign).
- Tools: tests/test_core.gd, tools/play.py flows, tools/balance.gd, tools/machine_pace.gd.

Known small open items: the "new: the bag!" popup can land on the trip postcard; balance note (a
huge scrapyard crew floods the bag); prices in automation are placeholders.

---

## Phase A: finish the early game (stage 1 → 2)

### A1. Pacing simulator for the whole early game  (ready)
- **Why:** automation, errands and the tree all pay in capsules now; nobody has checked the curve
  end to end. Emilia is testing timing by hand.
- **Build:** extend tools/machine_pace.gd (or a new tools/pace.gd) to play a simulated player:
  pull rate, repairs, errands levels, automation jobs, workers. Print minute-by-minute milestones
  (repairs, errands, better drops, automation, first worker) and coins/min per source. Suggest
  prices for data/automation.json.
- **Done when:** a report Emilia can read, with suggested numbers (not applied until she says).

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
  **Open questions for Emilia:** see docs/plans/A4.md (only blob's finishes page has a sticker;
  kinds per page and +10% each; washi tape name; what errands / automation cover; the dropped "fill
  the page for a surprise" line; numbers instead of words; old saves get their popups on load).
- **Verified (2026-09-28):** tests + flow book pass (every spread `expect fits`), and the flows
  whose big `pets` steps now fill pages (errand_jobs, errands_crowd, workers, fits) pass with
  `stickers off` / closing the popup.

### A5. The machine's later ideas  (needs prep)
- Rummaging → machine bits, pull value grows with income, a globe per map page, "better drops"
  mystery balls. **Prep:** which of these still matter now that automation exists.

---

## Phase B: stage 2, coins get semi-automated → chase packs and a rare pet

### B1. Pack tiers per map page  (VERIFIED 2026-09-28, merged)
- **Decided:** ~x5-10 cost per tier; a new tier appears in the shop when its **map page opens**
  (backyard tier 1, beyond the fence tier 2, zone 3 tier 3). A higher tier has ALL of: better
  rarity odds, more pets per box (2-3), gated finishes (some only from a tier up), gated parts
  (some body parts/palettes only exist from a tier up: new looks to collect).
- **Prep:** shop mockup (2-3 looks); tier names.
- **Build:** data/boxes.json tiers, gating in PetRoller, the boxes tab shelf, balance numbers.
- **Built:** sunny / sunset / midnight boxes (data/boxes.json: page, stamp, pets, arrives; priced in
  capsules 50 / 400 / 3200 through GameState.box_price), gated finishes and new looks (parts.json
  `from`), lucky box retired (BoxShop.fix_retired on every load: lucky -> sunset; save v26 adds
  boxes_bought + boxes_greeted), look C shop (counter row per tier with stamp, new looks stickers,
  inside shapes; stash pile per tier; a switch per tier on the job card), a tier pops in once with a
  sparkle + "new!" until bought, one box with 2-3 pets = ritual for the best + "also inside",
  workers count boxes. Midnight waits for the next-door page (E2). Flow box_tiers. Questions for
  Emilia in docs/plans/B1-done.md.

### B2. Multipliers  (partly decided)
- Book page boosts (A4, decided), knacks from the active pet's parts (D1, decided: knacks),
  toys (built), finds. Income must keep growing. **Prep:** where the player sees them all.
- **Built (lane b2-d1, merged):** B2 boost plumbing: `GameState.boost(kind)` /
  `boost_parts(kind)`, `Boosts` + data/boosts.json kind table, `toy_boost` removed. Sources: toys,
  the book's stickers, your active pet's knacks, the kitchen (errand speed; it multiplies now
  instead of adding to the tools' speed, so it's worth more with lots of tools). Kind `automation`
  = automation speed (crank, box opening, workers; not adventures). Receipt UI by the coin pill
  still waits for its look.

### B3. Automation layer 2: pets restock and buy spots  (needs prep)
- **Emilia:** workers can open boxes but not buy them, machines must be bought and filled by hand
  (the irritant). Layer 2 removes those chores: the piggy bank already lets your pet buy boxes;
  next something that buys machines and puts new pets on them.
- **Decided 2026-09-28:** unlocked by **a find beyond the fence** (like the piggy bank; e.g. a
  clipboard: your pet can manage workers). **Lore: machines come from places you've taken**: old
  machines left in places your pets "visited", coins haul them home, each map page raises how
  many exist (invading and automating feed each other).
- **Prep:** the look (a layer switch on the automation tab), the find's name.
- Also: spot prices must flatten so thousands of workers are possible.

---

## Phase C: stage 3, pack opening gets automated → managing pets

### C1. The pets tab as containers  (DECIDED 2026-09-28; needs a mockup pick)
- **Emilia:** sections are **automatic, by rarity** (a shelf per rarity with a count, tap to open
  it), with favourites / the best ones **pinned at the top**. Needed before thousands of pets.
- **Prep:** mockup 2-3 looks.

### C2. Pets per second  (DECIDED where it shows)
- **Emilia:** once opening is automated you get pets per second; pets become the midgame
  currency. Shown as **a pill at the top of the automation tab** ("N pets a minute"), like errands'
  coins a minute, once box workers exist. **Prep:** what spends them first.

### C3. A place for "bad" pets  (DECIDED 2026-09-28 after the brainstorm)
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

---

## Phase D: late-mid, parts and grafting become the "woah"

### D1. Parts with modifiers  (DECIDED: knacks)
- Parts are a late feature already (40 trips). **Emilia:** changing your pet should be a "woah"
  moment once you know how pets roll; every part has modifiers.
- **Decided:** a part's modifier is **a named knack** (lucky paws: +luck, big ears: spots places...)
  whose size scales with rarity; your active pet's knacks boost everything.
- **Prep:** the knack list per slot, how it's shown.
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

### E1. Combat adventures and dungeons  (needs big design)
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

### E2. The next map page (zone 3) and the invasion lore  (needs prep)
- **Emilia:** you conquer the backyard, then intel opens places beyond; the real lore is invading
  and expanding your territory. **Prep:** zone 3's places, how its intel comes.

### E3. The hard dungeon unlocks sacrificing  (needs E1)

---

## Phase F: mid game, a new layer on pets

### F1. The sacrifice machine: upgrading parts  (DECIDED 2026-09-28; needs mockup)
- **Emilia:** old perfect pets go into a machine; the better the pet, the more likely one of its
  parts gets upgraded; probably a slot machine UI. Pitched: the reels are the pet's parts, where
  they stop picks the part; a better pet gives an extra reel or a nudge.
- **Picked: the "stuffed toys" bundle** (plushie logic: a miss just "lets out some stuffing",
  your pet cheers every spin; what you really do is feed pets to a machine to upgrade one
  favourite, and the game never says so). The machine runs F2's reels, see below.
- **Prep:** mockup 2-3 looks; the upgrade's name (see F2).

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
- **The darker currency (working names; name and colour decided later, when the machine is
  mocked up):**
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

### F3. Pets as currency, spent everywhere  (needs design)
- **Emilia:** pets are a stepping stone: spent on automation, dungeons, adventures, scouting,
  tech, science, to earn the real currency that moves you on.

---

## Phase G: shipping

- Care / the desktop pet (buffs and check-in rewards), sound pass, real art, the Windows build
  (WindowSource backend), Steam page and rating (target PEGI 7-12; loot-box law notes in
  docs/design.md).

---

## Cross-cutting (do when a step needs it)

- **X1. Navigation space:** the spine fits about 8 tabs + settings; it's full now (automation made
  it 8). The next tab (gear) needs a plan: group tabs, a second column, or tabs that live inside
  others (e.g. gear inside adventures). **Done for A2:** gear lives inside adventures (adventures |
  upgrades), no new tab.
- **X2. GameState is big (~2400 lines):** split into parts (machine, errands, automation, runs)
  when a step touches it anyway.
- **X3. Tuning numbers in data/**, not code (some still in game_state.gd).
- **X4. Tests:** done. `tests/test_core.gd` now tests GameState itself in a test profile
  (`_test_game_state`, run with `-- --profile=core-test-<lane>`): save migrations v14..now plus a
  round trip, crank catch-up with and without the stool, the auto-adventure loop, thousands of
  workers with time limits, gear (A2) and the jar, kitchen and scouting (A3). It found that sending
  hundreds of auto parties was slow with many pets, and that is fixed.
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

## Tonight (2026-09-28, Emilia): prep + build the decided steps

Allowed: the sim report (numbers as suggestions only, not applied), tests (X4), brainstorms (C3
bad pets, F2 new layer, more gear upgrades), mockups for the open looks (B1 shop, C1 pets tab,
B3 layer switch, F1 sacrifice machine), and BUILD the decided steps (A2 gear page in adventures,
A3 savings jar + kitchen + scouting, A4 book rewards) with flows and screenshots, pushed to `test`
in small commits.

## Suggested order

A1 (sim) → X1 (navigation) → A2 (gear) → A4 (book rewards) → B1 (pack tiers) → B3 (automation
layer 2) → C1 (pets containers) → C2/C3 → D1 → E1...

Each step's **Prep** can be done ahead: answering its questions or picking its mockup look makes
it ready, so a long unattended run can build ready steps back to back.
