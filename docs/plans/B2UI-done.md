# B2UI done: the boost receipt (look A, the dark till roll) + "why so much?" tapes

## What was built
- **The tag:** a dashed cyan "x1.51" pill right after the coin pill (the coins boost total). It stays
  hidden until coins have a boost part (a toy playing or a favourite, or your active pet's coin
  badges). It turns solid pink while the receipt is open. Tap it to open the receipt, tap again to
  fold it. Switching tabs also folds it, and so does coins losing their last boost.
- **The receipt:** a dark torn receipt, 260 x 320, that prints out of a slot under the tag. It unrolls
  from the top in 0.22 s and folds back the same way.
  - It shows "our boosts" and the date and time ("tue 29 sep, 00:11"), then a dashed rule.
  - Each kind gets a header (its icon, its name from boosts.json, and its total: cyan for coins,
    pink for the rest), then one dotted-leader line per part.
  - It ends with "thank you, come again ♪" and a barcode.
  - With more lines it grows down to the page bottom, then the lines scroll inside it (a thin lilac
    bar, with room kept for it). It never goes past the window.
  - It shows shared boosts only: toys (by edition name, "holo acorn") and the active pet's badges
    ("big ears + one big eye").
  - It sits over the tab and under the pet's speech bubble.
- **"Why so much?" tapes:** a pink washi strip (see-through pink, torn ends, tilted) where coins land.
  Tapping it opens a small dark torn slip (214 wide) and tapping again folds it. The slip shows the
  start line, one dotted-leader line per multiplier (lines at x1 are left out), a dashed rule, then
  "all together" and the big cyan number. A tape only shows once its slip has at least one line.
  - Trip postcard coins: "found on the way", then "a tote bag" (the gear's name), "the party's
    badges" and "our boosts" (loot x coins), then the coins on the postcard. The postcard gets
    10 px more room above its stickers when the tape shows.
  - Errands income pill: "the crews" (coins a minute with no tools, level-0 goals and no tips), then
    "our tools", "job levels", "tips" and "our boosts" (errands x coins), then the pill's number.
    The slip is right-aligned under the pill. The tape holds the pill's top left corner, so it
    covers none of the words.
  - The machine's "N coins a capsule" line: "a capsule" (base_coins), then one line per bought coin
    upgrade by name ("tape up the crack x2.00", "shinier coins x1.95"), then "our boosts", then
    the line's number. The tape sits at the end of the line. It is hidden during the tutorial and
    during fever (the line says something else then).
- No maths changed: `tools/balance.gd` output is byte-identical to HEAD (diffed against a clean
  `git archive HEAD` export).
- **Review fixes (B2UI round 2):**
  - Z order is now UiTheme constants: `Z_TAPE` 2, `Z_SLIP` 3, `Z_PAPER` 4, `Z_PRIZE` 4,
    `Z_BUBBLE` 5, `Z_POPUP` 10. UnlockPopup and TutorialGuide sit at `Z_POPUP`, so the popup's dim
    covers the tapes, slips, receipt and bubble. UnlockPopup has a new `shown` signal, and home.gd
    folds the receipt on it.
  - The machine's PrizePopup is at `Z_PRIZE`, so a prize lands over an open slip.
  - `errands_per_minute()` is now `_errands_layered(true, true, true)` x boost("errands") x
    boost("coins"). `job_rate` goes through `_job_plain_rate(job, with_tools)`. The tool numbers come
    from `_job_tool_numbers` (fills the `_job_tools` cache). `job_boost(job, with_tools, with_goals,
    with_tips)` and `job_tips(job, with_tools)` take switches (defaults unchanged). The tips without
    the cups are cached under "<job>|plain".
  - Errands slip layers: plain tips, then tools, then goals. The fancy cups now land in "our
    tools", not "tips". The lines still show in the order our tools, job levels, tips.
  - The machine stage works out the capsule line every 0.2 s into `_line` (shared by `_draw_counter`
    and the tape). It moves the tape only when the line changes, and not while the tape is hidden.
  - test_core `_test_whys_add_up`: a GameState of its own (nothing saved). The capsule why and the
    errands why (plain, with tools, with the cups) multiply up to their totals, and the cups
    count under our tools.

## Files
New:
- `scripts/ui/boost_tag.gd` (`BoostTag`)
- `scripts/ui/boost_receipt.gd` (`BoostReceipt`, plus the shared paper drawing: `draw_paper`,
  `paper_points`, `barcode`, `rule`, `leader`)
- `scripts/ui/why_tape.gd` (`WhyTape`, `WhyTape.wrap`, inner `TapeBox` StyleBox)
- `scripts/ui/why_slip.gd` (`WhySlip`)
- `tests/flows/receipt.flow`

Changed:
- `scripts/core/boosts.gd`: `times`, `receipt`, `why`.
- `scripts/machine/toys.gd`: `Toys.edition_name` (moved out of `ToysView._edition_name`, which now
  calls it).
- `scripts/pets/knacks.gd`: `Knacks.part_names`.
- `scripts/machine/machine.gd`: `Machine.coin_parts`.
- `scripts/game_state.gd`:
  - `boost_receipt`, `_boost_line_name`, `capsule_why`, `errands_why`, `_errands_layered`,
    `_coin_gear_name`.
  - `_boost_trip_loot` now returns the coins' why. `collect_run` adds `coins_why` to the trip.
- `scripts/ui/expanded_view.gd`: `boost_tag`, `receipt`, the `_paper` overlay, `fold_receipt`,
  `_place_receipt`. `show_tab` folds the receipt.
- `scripts/ui/postcard.gd`: `coins_why`, the coin chip wrapped with its tape.
- `scripts/ui/errands_tab.gd`: the income pill wrapped (`right`).
- `scripts/ui/machine_tab.gd`: `MachineStage.why_tape`, `_counter_line()` (shared by the drawing
  and the tape).
- `scripts/dev/dev_driver.gd`:
  - New steps: `play`, `favourite`, `why`.
  - `expect fits` also checks every visible BoostReceipt and WhySlip is inside the window.
- `tests/test_core.gd`: `_test_receipt`, `_test_whys_add_up`.
- `scripts/ui/ui_theme.gd`: the `Z_*` constants.
- `scripts/ui/unlock_popup.gd`, `scripts/ui/tutorial_guide.gd`: z `Z_POPUP`; the popup's `shown` signal.
- `scripts/home.gd`: folds the receipt when a popup shows.
- `data/boosts.json`: `_note` only (sources and name are now shown on the receipt).
- `docs/design.md` (Boosts paragraph: the receipt and the tapes) and `docs/architecture.md` (Boosts
  section: two new bullets).

## Data shape
No new data file. The receipt's words ("our boosts", "thank you, come again ♪", "all together",
the slip line names) stay in code, like other UI words. Kind names come from `data/boosts.json`
`name`. Icons are `coin` for coins and `knack_<kind>` for the rest.

Receipt rows (`GameState.boost_receipt()`):
```
[ { "kind": "coins", "name": "coins", "total": 1.51,
    "lines": [ { "source": "toys", "name": "holo acorn", "x": 1.25 },
               { "source": "knacks", "name": "golden touch", "x": 1.21 } ] }, ... ]
```
A why (the trip's `coins_why`, `capsule_why()`, `errands_why()`):
```
{ "start": { "name": "found on the way", "value": 47 },
  "lines": [ { "name": "a tote bag", "x": 1.30 }, { "name": "our boosts", "x": 1.51 } ],
  "total": 92 }
```

## Save
No change and no SAVE_VERSION bump. `coins_why` lives only on the dictionary `collect_run` returns.

## Merge notes
- Book stickers (A4) and the kitchen: when they append their parts in `GameState.boost_parts`, give
  them a case in `GameState._boost_line_name` (for example "a paint set", "the kitchen").
  Otherwise their lines read as the raw part id.
- A lane that changes `_boost_trip_loot` must keep returning the why dictionary (collect_run reads
  it).

## Dev steps (new)
- `play <toy> [finish]`: your pet has a quick play with that toy (you must have it).
- `favourite <toy> [finish]`: you have that edition at the top level (a favourite, always on).
- `why <trip|errands|machine>`: logs that slip, e.g. `why trip: found on the way 13, a tote bag
  x1.30, our boosts x7.13 = 120`. `trip` reads the postcard on screen.

## Flows
- New: `receipt`, which does all of this:
  - Checks there's no tag before a boost.
  - Plays the holo acorn, then opens the receipt on all nine tabs with `expect fits`.
  - Dresses the pet with badges and adds seven favourites for a long receipt (`receipt_long`),
    then more favourites for a scrolling one (`receipt_scroll`).
  - Folds the receipt.
  - Opens each tape and checks its slip:
    - The machine (tape, oil, flap, wires, shine 3).
    - Errands (the basket, paws 3, noses 2).
    - The old trip's postcard: the tote bag isn't on it.
    - A new trip with `gear tote 2`: "a tote bag" is on it.
  - A golden prize with the machine slip open (`prize_over_slip`: the picture is over the slip).
  - An unlock popup with the slip and the receipt open (`popup_over_why`: the dim covers the tape
    and the slip, and the receipt folded).
  - Logs every slip with `why`.
- Re-run, all PASSED: fits, toys, knacks, postcard, errands, errand_tools, machine, automation, gear.
  After the review fixes: receipt, fits, errands, errand_tools, tutorial.
- Shots: `~/.local/share/godot/app_userdata/Desk Pets/profiles/play-receipt-receipt/shots/`.

## Checks
- test_core: ALL PASSED (3552 checks). `_test_receipt` covers:
  - The `times` format.
  - Name helpers.
  - Receipt grouping and order: kinds in table order, toys before badges, unknown sources last.
  - Totals.
  - `coin_parts` multiplied up equals `coin_value`.
  - `why` drops x1 lines: 47, x1.30, x1.51 gives 92.
- balance: byte-identical to HEAD.

## Text to add elsewhere at merge

**docs/dev-plan.md, under "### B2. Multipliers"** (add as a line):
```
- **Built (B2UI):** the receipt, look A (the dashed "x1.51" tag by the coin pill, the dark torn
  receipt "our boosts" by kind, shared boosts only) and the "why so much?" tapes on the postcard's
  coins, the errands pill and the machine's capsule line. Book stickers and the kitchen join the
  receipt through `GameState._boost_line_name`.
```

**CLAUDE.md "Where we left off"** (add a bullet):
```
- B2UI (lanes/receipt): the boost receipt, look A (the dark till roll). BoostTag "x1.51" by the coin
  pill (hidden until coins have a boost) opens BoostReceipt (dark torn paper, a header per kind
  with its total, dotted-leader lines, "thank you, come again ♪" + barcode; grows to the page
  bottom, then scrolls; folds on a tap or a tab switch). GameState.boost_receipt() via
  Boosts.receipt; line names in GameState._boost_line_name (toys: Toys.edition_name, knacks:
  Knacks.part_names). "Why so much?" WhyTape + WhySlip (Boosts.why) on the postcard coins
  (trip "coins_why" from _boost_trip_loot), the errands pill (errands_why) and the machine's
  capsule line (capsule_why, Machine.coin_parts). No save change. Dev steps play, favourite,
  why; flow receipt; `expect fits` also checks floating papers.
```

## Questions for Emilia
- Should the receipt fold when you switch tabs? It does now. The mockup only folds it on a tap.
- The machine slip names every coin upgrade (up to 9 lines) instead of grouping them. OK?
- Is the errands slip split right: the crews, our tools, job levels, tips, our boosts?
- Is "the party's badges" the right wording for the party's own knacks on the trip slip?
- The receipt keeps the mockup's 320 height even with one line, so a short list leaves the middle
  empty. Should it shrink to fit instead?
- The postcard and errands tapes tilt up to the right, the other way from the mockup, so they don't
  cover the coin number or the pill's words. The machine's tape keeps the mockup's tilt. OK?
- The pet's speech bubble draws over the receipt when a long line grows down. OK?
- A prize picture now draws over the open machine slip, and the slip stays open after the pull
  (it isn't folded). OK?
