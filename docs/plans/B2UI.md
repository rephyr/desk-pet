# B2UI: the boost receipt (look A, the dark till roll) + "why so much?" tapes

Built on the B2 plumbing (`GameState.boost(kind)` / `boost_parts(kind)`) and D1 knacks already on
this branch. Shared sources here: toys and the active pet's knacks (its badges). Book stickers and
the kitchen are not on this branch; they show up on the receipt by themselves once they append their
parts (merge note: give them a line name in `_boost_line_name`). No maths changes, so
`tools/balance.gd` output must stay byte-identical.

## Files

New
- `scripts/ui/boost_tag.gd` (`BoostTag`, a Button): the dashed cyan "x1.51" pill beside the coin
  pill. Draws its own dashed rounded border (StyleBoxFlat can't dash); "on" = solid pink border on
  pink_pressed. Hidden while `boost_parts("coins")` is empty. Tap toggles the receipt.
- `scripts/ui/boost_receipt.gd` (`BoostReceipt`, a Control): the dark torn receipt. Also holds the
  static drawing helpers both papers use: `draw_paper(ci, rect, fill, stroke, tooth)` (straight top,
  zigzag bottom), `draw_barcode(ci, at, color)`, `leader_line(name, value)` (name, dotted leader,
  value; the name clips with an ellipsis).
- `scripts/ui/why_tape.gd` (`WhyTape`, a Button): the pink washi "why so much?" strip, tilted 8
  degrees with torn ends. Tap toggles its slip.
- `scripts/ui/why_slip.gd` (`WhySlip`, a Control): the small dark torn slip, 214 wide: the start
  line, one leader line per multiplier, a dashed rule, "all together" + a big cyan number.
  `mouse_filter` ignore (the tape folds it).
- `tests/flows/receipt.flow`.

Changed
- `scripts/core/boosts.gd`: `times(x) -> String` ("x1.25"; "x12.5" from 10; `UiTheme.num`-style
  "x1.2k" from 1000), `receipt(catalog, parts_by_kind, namer)` (groups into kinds in boosts.json
  order, lines in `sources` order, drops kinds with no parts, totals each kind), `why(start_name,
  start_value, lines, total)` (drops lines within 0.005 of x1). Still imports no game system (names
  come through the `namer` Callable).
- `scripts/machine/toys.gd`: `Toys.edition_name(catalog, edition)` ("holo acorn"; moved out of
  `ToysView._edition_name`, which now calls it).
- `scripts/pets/knacks.gd`: `Knacks.part_names(catalog, id)` ("body:bunny+eyes:cyclops" ->
  "big ears + one big eye").
- `scripts/machine/machine.gd`: `Machine.coin_parts(state, catalog)` -> `[{ id, name, x }]`, one per
  bought node with `coins_x` (x = coins_x ^ level), tree order. Its product is `coin_value / base`.
- `scripts/game_state.gd`:
  - `boost_receipt() -> Array` (via `Boosts.receipt`, every kind's `boost_parts`), `_boost_line_name(part)`.
  - `_boost_trip_loot` returns the coins "why" (same maths, now also recorded); `collect_run` puts
    it in the trip dict as `coins_why`.
  - `capsule_why()`, `errands_why()` (below).
- `scripts/ui/expanded_view.gd`: the tag after `_coins`; an overlay Control on the page (a
  MarginContainer child, so it fills the page and draws over the tab) holding the receipt top
  right. The receipt folds when you switch tabs.
- `scripts/ui/postcard.gd`: the coin chip sits in a plain Control box with its tape (top edge,
  40 px in) and slip (under the chip, floating over the parts, z above).
- `scripts/ui/errands_tab.gd`: the same box around the income pill; the slip opens under the pill,
  right-aligned so it stays inside the window.
- `scripts/ui/machine_tab.gd`: the tape as a child of MachineStage, placed from design space under
  the "N coins a capsule" line (moves with the stage's scale); the slip under it.
- `scripts/dev/dev_driver.gd`: steps `play <toy> [finish]` (a quick play, no clicking through the
  toys page) and `why <trip|errands|machine>` (logs the slip lines).
- `tests/test_core.gd`: `_test_receipt`.
- `docs/design.md`, `docs/architecture.md` (small sections), `docs/plans/B2UI-done.md`.

## Data shape

No new data file. Receipt words ("our boosts", "thank you, come again ♪", "all together", slip
line names) stay in code, like other UI words. Kind names and icons come from `data/boosts.json`
(`name`) and `UiTheme.DOODLES["knack_<kind>"]` (every kind has one already).

Receipt rows (`GameState.boost_receipt()`):
```
[ { "kind": "coins", "name": "coins", "total": 1.51,
    "lines": [ { "source": "toys", "name": "holo acorn", "x": 1.25 },
               { "source": "knacks", "name": "golden touch", "x": 1.21 } ] }, ... ]
```
A "why" (trip `coins_why`, `capsule_why()`, `errands_why()`):
```
{ "start": { "name": "found on the way", "value": 47 },
  "lines": [ { "name": "a tote bag", "x": 1.30 }, { "name": "our boosts", "x": 1.51 } ],
  "total": 92 }
```
- Trip: start "found on the way" = coins before boosts; lines = the tote (the gear's name, from
  data/gear.json), "the party's badges" (party knacks on loot), "our boosts" (`boost("loot") *
  boost("coins")`); total = the coins on the postcard.
- Machine: start "a capsule" = base_coins; one line per `Machine.coin_parts` node (its name, e.g.
  "tape up the crack x2.00", "shinier coins x1.95"); "our boosts" = `boost("coins")`; total = the
  counter's "N coins a capsule".
- Errands: start "the crews" = coins a minute from the crews with no tools, level-0 goals and no
  tips; lines "our tools", "job levels", "tips" (each is the ratio of the per-minute totals with
  that layer added, since each job differs), "our boosts" = `boost("errands") * boost("coins")`;
  total = `errands_per_minute()` (the pill).
- A tape only shows when its why has at least one line (hidden until earned). The machine's also
  waits for the tutorial to end.

## Save

None. `coins_why` lives on the trip dict from `collect_run`, not in the save. No SAVE_VERSION bump.

## UI sketch

```
 [bubble ...............] (◆ 12.4k) [x1.51] (★ 2,310) ▾ ×
                                      ┌═══════════════════┐   <- the slot (lip, lilac seam)
                                      │    our boosts     │   pink title, muted date/time
                                      │  mon 28 sep, 14:02│
                                      │ - - - - - - - - - │
                                      │ ◆ coins     x1.51 │   kind header: icon, lilac name, total
                                      │   holo acorn  x1.25   (coins total cyan, others pink)
                                      │   golden touch x1.21
                                      │ ♣ luck      x1.15 │
                                      │   ladybug ... x1.15
                                      │ thank you, come   │
                                      │ again ♪   ||||||| │   muted, barcode
                                      └/\/\/\/\/\/\/\/\/\/┘   torn bottom
```
- 260 wide, 320 tall; grows taller for more lines up to the page bottom (8 px gap), then the lines
  scroll (thin scrollbar) so it never spills. Opens with a quick print (scaleY from the slot, 0.22 s),
  folds back the same way. The tag is solid pink while open.
- Postcard: `(◆ 92)` with a pink washi "why so much?" across its top edge; the slip hangs under it:
  `found on the way .... 47 / a tote bag .... x1.30 / our boosts .... x1.51 / - - - / all together  92`.
- Errands pill and the machine's capsule line get the same tape and slip.
- No dropdowns, no '·', no hint text, nothing locked or greyed.

## Flow steps (tests/flows/receipt.flow)

```
from after_tutorial
view full
expect no-text "our boosts"          # no source: no tag
shot no_tag
toy acorn holo 1
play acorn holo
wait 0.5
click BoostTag#1
wait 0.4
expect text "our boosts"
expect text "holo acorn"
expect text "thank you, come again ♪"
expect fits
shot receipt
(for every tab: tab X, click BoostTag#1, expect fits, shot receipt_X; tabs opened with unlock)
unlock feature:parts
dress body=... (a pet with several knack kinds, for a long receipt)
click BoostTag#1 ... expect fits, shot receipt_long
click BoostTag#1
expect no-text "our boosts"          # folded
tab machine / fix tape / fix shine 3 / click WhyTape#1
expect text "shinier coins" / expect text "all together" / expect fits / shot machine_why
(errands: fix oil, fix flap, find basket, tool paws 3, tab errands, click WhyTape#1, shot errands_why)
gear tote 2, send a trip, skip the walking, "welcome back", click WhyTape#1
expect text "a tote bag" / expect text "all together" / expect fits / shot postcard_why
why trip / why errands / why machine  (log)
```
Also re-run: toys, knacks, postcard, errands, errand_tools, machine, fits, automation, gear.

## Tests (tests/test_core.gd, `_test_receipt`)

- `Boosts.times`: 1.25 -> "x1.25", 1.0 -> "x1.00", 12.46 -> "x12.5", 1234 -> "x1.2k".
- `Boosts.receipt`: no parts -> []; two acorns + the moth playing -> a coins row with 3 lines named
  by `Toys.edition_name` ("holo acorn", "acorn", "moth"), its total = `Boosts.total` of the parts;
  luck row has the moth; kinds in boosts.json order, lines in `sources` order (a fake knacks part
  lands after toys); kinds with no parts left out.
- `Knacks.part_names`: "body:bunny+eyes:cyclops" -> "big ears + one big eye".
- `Machine.coin_parts`: fresh machine -> []; tape + shine 3 -> 2 lines (x2, x1.953), product x base
  = `Machine.coin_value`.
- `Boosts.why`: lines at x1 dropped; the trip case start 47, tote 1.30, boosts 1.51 -> total 92
  (the same `roundi` as `_boost_trip_loot`).
- Balance: `tools/balance.gd` output identical before and after (diffed).

## Questions for Emilia

- The receipt folds when you switch tabs (the mockup only folds on a tap). OK?
- The machine's slip lists every coin upgrade by name (up to 9 lines) rather than grouping them.
- The errands slip splits into "the crews", "our tools", "job levels", "tips", "our boosts".
- The trip slip calls the party's own loot knacks "the party's badges".
- Tag and receipt sit under the pet's speech bubble when a long line grows down over them.
