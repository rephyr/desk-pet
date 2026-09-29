# E1 done: the old well dungeon (look A, the cross-section) + lanterns (wisps)

## What was built
The well line is one dungeon. The top of the well stays a trip (now `max_party` 100: no swarms down
the well line); a party of 100 there can find "the rope goes further down" (event `well_rope`,
find `deep_rope`, `min_party` 100), which opens `feature:dungeon`: a third page in adventures
(adventures | upgrades | dungeon; each button only once its page is there; a coral lantern chip
with the wisps by the switch on the dungeon page). The cellar and further down are no longer trips:
they're bands of the well (`"band"` in data/adventures.json, never open, not on the map; runs
already out there still come home). Their rumours are `"retired"` (never heard again).

- **Bands (data/dungeon.json):** the well 1-10 (rope floors: only the front row fights), the cellar
  11-20 (doors; tiny doors on 13/17 let only rare+ through; knock-back doors on 15/19 roll luck:
  a miss sends the army home, no losses, no pay for that floor), further down 21+ (stairs forever,
  a guard every 10th at x2 strength). A band shows once the army has stood at its top (deep >=
  from - 1) or an old save had its place open.
- **The army:** card pets you add (tap the front row: a picker of resting cards by power, 5 x 4 a
  page, "best ones" = the strongest 20, "done") + herd pets by shelf (a stepper per rarity, steps
  of 10, "of N" = resting + already in the army). The best 20 cards by power fight in front; cards
  past 20 ("+N") and the herd walk behind at `herd_x` 0.5; injured at `injured_x` 0.5. Power =
  power stat with traits (`Party.stat_of`) x rarity_x x finish_x x the pet's own power knack;
  herd pets use `Herd.template` stats; the army x `boost("power")`. Your active pet's card leads
  the front row with a pink flag (21 cells, 7 x 3) but never fights or falls. The entrance fits
  300. Army pets are reserved while home too: not resting, not sendable, not on errands/workers,
  never folded into the herd (`GameState._out()` = away + army; herd picks are spread over counts
  after everyone else's, `_army_herd`).
- **Floors:** strength 100 x 1.2^n, only ever shown as feeling words (easy peasy, a stroll, comfy,
  spooky, tricky, so tough, brr!) on the next 6 floors of the column and a pill on the orders card
  (no words while the army is empty).
- **Orders card (tilted index card, steppers only):** "go down to floor ‹N›" (1 .. deepest + 5,
  inside the bands shown), "come home when ‹30%› are gone" (10..90), and once the cellar is reached
  (deep >= 11) "who goes first ‹plain ones / anyone / the front row›". Before that losses take the
  injured first, then anyone. "down we go!" / "on the way…".
- **A run** is simulated when it sets off (`Dungeon.simulate`, 20 s a floor): per floor
  injure/ratio get hurt, lose/ratio² don't come back (each at most 25%); a floor below 0.4 of its
  strength can't be passed (its losses happen, no pay, they turn back). Stops at the target, at
  "home when X%", at a missed knock door. Pay per cleared floor = 0.01 x 1.15^floor x min(sent,
  entrance), rounded, at least 1; never looks at losses. Gear is never read.
- **Home:** `_finish_dungeon_run` (the 1-second tick): lost cards via `Collection.remove`, lost
  herd via new `Collection.lose_plain(key, n)` (a star each, never a word about them), wisps paid,
  deep + bands updated, "last time" card (got to floor N / brought home (lantern) N / came home N),
  your pet's line (home / home early / new deepest).
- **Firsts (once):** floor 10 = a rolled epic part + unlock `lead_army` (earn key `floor`), which
  teaches your pet the automation job `army` straight away (new unlock field `learns`). Floor 20 =
  find `little_key` with one quiet line; nothing is drawn on floor 20, before or after.
  While `feature:parts` is closed, floor 10's part waits (firsts["10"] stays unset, its glint is
  hidden) and pays on the first clear after parts open.
- **Lead the army** (automation job `army`, icon lantern, colour wisp, JobScene draws a little
  well): while it's your pet's task, the same army with the same orders goes down again whenever
  it's home (the 1-second tick: while the game runs, and on the first tick after loading).
- **Wisps = the darker currency** (the word lives in dungeon.json `currency`; colour role `wisp`,
  candy floss coral, in all 5 themes; `UiTheme.WISP`, doodle + pixel icon `lantern`). Nothing
  spends them yet; the entrance level is saved for the first buy.
- **Knacks:** `power` is a boost kind now (data/boosts.json) and its knack kind opens with
  `feature:dungeon`, so the little horns show once the dungeon is open.
- Night sky redraws when the army comes home (herd stars). Pet details: "down the well…" for a
  card that's down there.

## Files
- New: data/dungeon.json, scripts/dungeon/dungeon.gd (`Dungeon`), scripts/ui/dungeon_view.gd
  (`DungeonView`), scripts/ui/well_column.gd (`WellColumn`), scripts/ui/front_row.gd (`FrontRow`),
  tests/flows/dungeon.flow
- Changed: data/adventures.json (well max_party + well_rope event, cellar/below `band`, rumours
  `retired`, note), data/unlocks.json (unlocks dungeon + lead_army, finds deep_rope + little_key,
  note: `floor`, `learns`), data/automation.json (job army), data/boosts.json (power),
  data/knacks.json (power opens feature:dungeon), data/themes.json (wisp), data/voice.json
  (automation_do/stop_army, dungeon_* lines), scripts/core/catalog.gd (`catalog.dungeon`),
  scripts/game_state.gd, scripts/pets/collection.gd (`lose_plain`), scripts/adventure/rumours.gd
  (retired), scripts/ui/adventures_tab.gd (3-page switch, wisp chip, `show_named_page`),
  scripts/ui/expanded_view.gd (`show_tab("adventures:dungeon")`), scripts/ui/automation_tab.gd,
  scripts/ui/pet_details.gd, scripts/ui/night_sky.gd, scripts/ui/ui_theme.gd, scripts/dev/dev_driver.gd,
  tools/balance.gd (dungeon table), tests/test_core.gd (`_test_dungeon`, `_test_dungeon_game`,
  rumour/unlock/automation/knacks checks updated), docs/design.md, docs/architecture.md

## Data shape
data/dungeon.json: `strength {base, grow}`, `entrance {start}`, `front_row`, `herd_x`,
`injured_x`, `stuck`, `power {rarity_x, finish_x}`, `bands [{id, name, from, to?, kind, place,
tiny?, tiny_from?, knock?, knock_luck?, guard_every?, guard_x?}]`, `losses {lose, injure,
max_share}`, `pay {base, grow}`, `seconds_per_floor`, `target_ahead`, `home_at [..]`,
`home_at_start`, `first {lines, earn_floor}`, `words [[ratio, word, heat]]`, `firsts {floor:
{part: tier} | {find, say}}`, `currency {word, color}`.

## Save: v23 -> v24 (renumber at merge)
New fields `wisps` (int) and `dungeon` = `{ deep, bands, target, home_at, first, cards: [uids],
herd: { rarity: n }, run: {} | { at, floors: [{ f, cleared, lost_cards, lost_herd, pay }], why,
turned, cards, herd: { count key: n }, sent, target }, last: {} | { floor, got, back }, firsts:
{ "10": true }, entrance }`. Migration (`version < 24`, placed after the v7 block): bands = well +
each band whose `place` was `location:` unlocked (the unlocks stay); waiting rumours about band
places dropped; your pet's and workers' parties going to a band place go to the well. Loading reads
the dungeon before the jobs (army cards drop off crews) and keeps only army cards that exist,
aren't your active pet and aren't away.

## Flows and dev steps
- `tests/flows/dungeon.flow` (shots: found, empty, picker, army, running, home, lead_popup,
  automation, deep, map; `expect fits` on each). Also played: fits, gear, automation, knacks,
  workers, party, postcard (all pass).
- Dev steps: `dungeon` (the rope find), `army best`, `army-herd <rarity> <n>`,
  `orders <floor> <home%> ["who goes first"]`, `down`, `down-done`, `deep <n>`, `wisps <n>`.
  `page adventures 2` flips to the dungeon page.
- Checks: test_core ALL PASSED (3660), balance runs (new table: common+common armies reach ~6,
  uncommon+common stop at 12 (the tiny door), rare+uncommon ~19, epic+rare ~24).

## Text for docs/design.md
Already added as "## The old well (dungeon)" after "## Gear" (and the knacks line now says "power
until the dungeon opens").

## Text for docs/architecture.md
Already added: the `scripts/dungeon/` layer line, `DungeonView` / `WellColumn` / `FrontRow` in
Screens, and the v24 paragraph at the end of Saving.

## Text for docs/dev-plan.md (E1)
Replace the E1 "Prep" line with:
- **Built (E1, lanes/dungeon):** the old well dungeon, look A (the cross-section). data/dungeon.json,
  `Dungeon` (rules), `DungeonView` / `WellColumn` / `FrontRow` (the adventures tab's third page),
  save v24 (`dungeon`, `wisps`). The well trip caps parties at 100; a party of 100 finds the rope
  (`deep_rope`) that opens the dungeon; the cellar and further down are bands now (old saves keep
  them as reached). Army = cards you add (best 20 by power in front, your pet's flag) + herd by
  shelf, entrance 300; floors 100 x 1.2^n as feeling words; orders card (floor, home at X%, who
  goes first from the cellar); losses become stars; wisps per floor for pets sent. Floor 10: an
  epic part + "lead the army" (automation job `army`); floor 20: the tiny key (E3), hidden.
  Open: something that sends 100 pets at once (see questions), wisp spending (the entrance first).

## Text for CLAUDE.md "where we left off"
- E1 (lanes/dungeon): the old well dungeon, look A (the cross-section). data/dungeon.json,
  scripts/dungeon/dungeon.gd (`Dungeon`: bands, floor kinds, strength, pet/army power, feeling
  words, `simulate` works a whole run out when it sets off, pay), GameState dungeon part (army:
  `army_best` / `set_army_card` / `set_army_herd`, `set_order`, `send_army`, `_dungeon_tick`,
  `_finish_dungeon_run`; army pets are busy via `_out()` / `_army_herd`), `wisps` (the darker
  currency, colour role `wisp`, icon `lantern`), `Collection.lose_plain`, save v24 (`dungeon`,
  `wisps`; cellar/below become bands already reached). UI: adventures | upgrades | dungeon
  (`DungeonView`, `WellColumn`, `FrontRow`), wisp chip by the switch. Automation job `army` "lead
  the army" (learned at floor 10 via unlocks.json `learns`). Band places: `"band"` in
  adventures.json, retired rumours `"retired"`. Flow: dungeon; dev steps `dungeon`, `army best`,
  `army-herd <rarity> <n>`, `orders <floor> <home%> [first]`, `down`, `down-done`, `deep <n>`,
  `wisps <n>`.

## Questions for Emilia (smallest safe pick used meanwhile)
1. **Nothing sends 100 pets at once yet.** Parties top out at 10 (the hay wagon); the old
   "automation" swarm unlock isn't granted by anything now. So the rope find (min_party 100, as
   picked) can't turn up in normal play on this branch. Should the whistle (B3) or something else
   open big parties, or should the rope need fewer (e.g. 10)?
2. **The whistle gate:** B3 isn't on this branch; the merge should add `"after": "whistle"` to the
   `well_rope` event.
3. **Currency word:** picks say "wisps" (lanterns are the dungeon's source). The chip shows a
   lantern and the number; the pet says "wisps". The word is one line in dungeon.json.
4. **Nothing to spend wisps on yet** (widening the entrance is the first buy, the well-wall perk
   tree later). The entrance level is saved and read (`Dungeon.entrance`) ready for it.
5. **A wall:** a floor below 0.4 of its strength can't be passed (its losses happen, no pay, they
   turn back), so strength matters even with "come home when 90%". OK, or should armies always
   push through?
6. **Knock-back door miss:** home with no losses and no pay for that floor. OK?
7. **Army picks are reserved while home** (not resting, errands and sharing-out can't take them),
   so "lead the army" always finds the same army. OK?
8. **Your pet leads but never fights or falls** (its card with the flag isn't one of the 20). OK?
9. **Floor 10's part** is a random epic part (no dungeon-only part art yet).
10. **Lead the army** only runs while the game runs (plus the first tick after loading) and sends
    the army again straight away when it's home.

## Review fixes (after the first review)

- `army_choices()` builds its typed array step by step (no untyped `[]` into `Array[Pet]`).
- Sorting by power works each pet's power out once (`GameState._strongest_first`); `army()` also
  returns `keys` (the herd count keys); `GameState.army_rules(a)` + `floor_words(from, to, rules)`
  and `WellColumn.refresh(a, rules)` so one page rebuild builds the army once.
- DungeonView rebuilds on `dungeon_changed` straight away; herd/pets/jobs/adventures signals only
  rebuild when a key of what the page shows changed (army cards + herd keys + picks, sent, your
  pet, running, room per shelf, resting card count while picking), checked at most every 0.5 s and
  never while the left mouse button is held (a click never lands on a freed button).
- Floor 10's part waits while parts are closed (see Firsts); test added.
- `FrontRow.new(lead, cards, clickable, front_n)`: rows = ceil((front_n + 1) / 7), from data.
- `Dungeon._random` picks cards one by one but splits the herd's share over counts in one go
  (`Dungeon._split`, per-group rounding that keeps the total exact); `Collection.lose_plain` adds
  its stars in one step (`Collection._stars`, only up to fallen_keep kept).
- `GameState.take_dungeon_news()` (like take_announcement); `in_army()` removed (unused; the pet
  card's "down the well…" means sent, not picked, so it keeps its own check).
- No save change from these fixes.

## Verified

- Step verified: test_core ALL PASSED (3661 checks), balance runs clean, dungeon flow + fits pass.
- Commits on lanes/dungeon: "the old well dungeon, with review fixes" (the step), plus this note.
  Not pushed. Save bump v23 -> v24 needs renumbering at merge.

## Merged into lanes/merge (2026-09-29)

- Save: the lane's v23 -> v24 is **v33** here (after C2's v32). `_migrate` runs it as `version < 33`
  (after the v7 block); the test save in `_test_dungeon_game` is a v32 one.
- `well_rope` waits for the whistle (`"after": "whistle"`); the well keeps B3's `well_whistle` and
  A5's pulley treat. Cellar/below keep the merge's `sunset` boxes and get `"band"`; the `edge`
  rumour stays next to the retired ones.
- `GameState.all_places_open` skips band places (the edge's "every place on beyond is open" could
  never be earned otherwise). `_open_entry` (the merge's shared unlock opener) handles `learns`.
- `ExpandedView.show_tab(tab_id, unlock_id)` takes both B3's unlock id and this lane's
  "adventures:dungeon" page. The dungeon lane's own b2-d1 merge (PetCard, MiniCard badges) was
  dropped for the merge's; `Collection.lose_plain` sits next to `leave` / `take_plain` / `add_stars`.
- dungeon.flow: `stickers off` (300 pets can fill a book page) and `map-page beyond` for the last
  shot. Played: dungeon, fits, tutorial, automation, workers, whistle, knacks, party, postcard, gear,
  edge, school, next_door, new_homes, pets_shelves, receipt, unlock_popup (all pass);
  test_core ALL PASSED (5097), balance runs.
