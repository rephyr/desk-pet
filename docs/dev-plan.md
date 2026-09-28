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

## BRAINSTORM FIRST (Emilia, 2026-09-28)

Everything below still needs brainstorming. Run these first (Emilia runs a brainstorm workflow
after /clear), then bring the options back to her as questions (AskUserQuestion rounds, she picks;
no guessed work), and write her picks into the steps.

1. **More gear upgrades** (A2): besides walk speed and bigger bags, what xp buys on the
   adventures upgrades page. Seed ideas: sharper eyes (more spotting, rumours, trail pickups),
   comfy harness (hurt less often), trail snacks (heal a heart on the way home), lucky charm
   (risky choices go well more often), more trip slots.
2. **Bad pets** (C3): once packs open per second, overflow pets pile up and become obsolete. How
   do they clear? Seed: auto sacrifice, put to work, feed the sacrifice machine, sell, part them.
3. **The new layer on pets** (F2): what makes a perfect pet really, really hard again in the mid
   game, with a gambling loop more complex than a lever (so pets can't automate it at first).
   Seed: part levels/stars from the sacrifice machine, a new axis (soul, aura, mutation).
4. **The darker currency** (F2): what it is and what it buys (the name is decided later; "perk
   points" is the working name).

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

### A2. Gear: xp upgrades  (DECIDED 2026-09-28, waits for brainstorm 1)
- **Emilia:** an "upgrades" page INSIDE the adventures tab (adventures | upgrades, like machine |
  upgrades), not its own tab. Look: gear.html's crayon path of gear stickers, words not numbers.
  Opens with the first xp. First upgrades: **walk speed** (shorter trips), **bigger bags** (more
  coins/loot home), plus the ones brainstorm 1 picks.
- **Look (picked 2026-09-28):** gear.html's crayon path (stickers along a path, buying reveals the
  next ones), but **effects show as numbers** ("trips 10% shorter"), like the errands pegboard.
- **Waits for:** brainstorm 1 (the rest of the upgrade list).
- **Build:** data/gear.json, a pure Gear rules class, GameState xp spending, a GearView page in
  AdventuresTab, flow.

### A3. More errand jobs  (DECIDED 2026-09-28, ready)
- **Emilia picked:** savings jar (fills slowly, pays one big chunk), kitchen (brings nothing,
  every job a bit faster, SOFT: a few cooks ~+10-25% diminishing, never beats real jobs; feeds
  your pet), scouting (raises the spot/rumour chance of the next trips; CHANCE ONLY, the map's ?
  clouds stay a surprise).
- They open through **goals on job levels**, like the lemonade stand (e.g. lemonade lv 10 → the
  savings jar; coin hunt lv 25 → the kitchen; a later goal → scouting).

### A4. Book page rewards  (DECIDED 2026-09-28, ready: mockup design/mockups/screens/book.html)
- Filling a collection book page opens its reward sticker: a **small permanent boost** (the book
  becomes a multiplier source). Kinds: **coins %, luck, automation speed, errands**.

### A5. The machine's later ideas  (needs prep)
- Rummaging → machine bits, pull value grows with income, a globe per map page, "better drops"
  mystery balls. **Prep:** which of these still matter now that automation exists.

---

## Phase B: stage 2, coins get semi-automated → chase packs and a rare pet

### B1. Pack tiers per map page  (DECIDED 2026-09-28; needs a shop mockup pick)
- **Decided:** ~x5-10 cost per tier; a new tier appears in the shop when its **map page opens**
  (backyard tier 1, beyond the fence tier 2, zone 3 tier 3). A higher tier has ALL of: better
  rarity odds, more pets per box (2-3), gated finishes (some only from a tier up), gated parts
  (some body parts/palettes only exist from a tier up: new looks to collect).
- **Prep:** shop mockup (2-3 looks); tier names.
- **Build:** data/boxes.json tiers, gating in PetRoller, the boxes tab shelf, balance numbers.

### B2. Multipliers  (partly decided)
- Book page boosts (A4, decided), knacks from the active pet's parts (D1, decided: knacks),
  toys (built), finds. Income must keep growing. **Prep:** where the player sees them all.

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

### C3. A place for "bad" pets  (NEEDS A BRAINSTORM)
- **Emilia (2026-09-28):** early on they're **put to work** (workers, party fodder), later they
  **feed the sacrifice machine**. But once packs open per second, bad pets become obsolete and
  pile up: they need a way to clear, e.g. **auto sacrifice**. Brainstorm what to do with them
  (options with pros and cons) before designing.

---

## Phase D: late-mid, parts and grafting become the "woah"

### D1. Parts with modifiers  (DECIDED: knacks)
- Parts are a late feature already (40 trips). **Emilia:** changing your pet should be a "woah"
  moment once you know how pets roll; every part has modifiers.
- **Decided:** a part's modifier is **a named knack** (lucky paws: +luck, big ears: spots places...)
  whose size scales with rarity; your active pet's knacks boost everything.
- **Prep:** the knack list per slot, how it's shown.
- Grafting (sewing onto your active pet, can fail) exists; the workbench shows it.

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
- **Prep:** the first dungeon (floors, what it asks for), the policies UI.

### E2. The next map page (zone 3) and the invasion lore  (needs prep)
- **Emilia:** you conquer the backyard, then intel opens places beyond; the real lore is invading
  and expanding your territory. **Prep:** zone 3's places, how its intel comes.

### E3. The hard dungeon unlocks sacrificing  (needs E1)

---

## Phase F: mid game, a new layer on pets

### F1. The sacrifice machine: upgrading parts  (needs mockup)
- **Emilia:** old perfect pets go into a machine; the better the pet, the more likely one of its
  parts gets upgraded; probably a slot machine UI. Pitched: the reels are the pet's parts, where
  they stop picks the part; a better pet gives an extra reel or a nudge.
- **Prep:** mockup 2-3 looks; what "upgraded" means for a part (depends on F2).

### F2. A new layer on pets: perfect is hard again  (needs design)
- **Emilia:** the mid-game main goal: a new layer so a perfect pet is really, really hard again;
  a new gambling loop more complex than a lever (so pets can't automate it at first); it earns
  something darker than coins (maybe "perk points"), slowly at first, billions later. Old layers
  get abstracted and handed off to pets.
- **Emilia (2026-09-28):** brainstorm the layer (options with mockups later); the darker
  currency's name is decided later ("perk points" is the working name).

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
  others (e.g. gear inside adventures). **Prep:** mockup before A2.
- **X2. GameState is big (~2400 lines):** split into parts (machine, errands, automation, runs)
  when a step touches it anyway.
- **X3. Tuning numbers in data/**, not code (some still in game_state.gd).
- **X4. Tests:** the v21 migration, crank catch-up, the auto-adventure loop, many workers.

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
