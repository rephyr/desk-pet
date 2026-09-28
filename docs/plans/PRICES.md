# PRICES: errand tools and boxes priced in capsules

From docs/picks.md "Balance picks": errand tools and boxes pay in capsules (x Machine.coin_value,
which grows about x2500 over the machine tree), but cost fixed coins, so they get 2500x cheaper.
Now their prices grow with the capsule value the same way their pay does.

## The rule

    price in coins = base "capsules" x Machine.coin_value(machine)   (x grow^level for tools)

- Same capsule unit the errand pay uses (GameState.job_boost "coin_value"): the machine's plain
  capsule, no toy boost (toys are temporary).
- Rounded, at least 1 coin, capped at Jobs.MAX_PRICE (no int wrap).
- A tool or box without "capsules" keeps its old fixed "coins"/"price" (fallback). Automation
  spots also go through Jobs.tool_cost with "coins" and stay fixed (their prices are a separate
  merge item).

## Data shape

data/errands.json, every tool: `"coins": 180` becomes `"capsules": 2.5`.
Base = old coin price / 75. 75 is the capsule value when the basket opens for a steady player
(flap + shine 10; the A1 pace report measured 75 at minute 16), so prices when errands open stay
about the same as now. Rounded to tidy numbers:

| tool | coins now | capsules | coins at value 75 |
|---|---|---|---|
| noses | 180 | 2.5 | 188 |
| paws | 400 | 5 | 375 |
| pockets | 2500 | 33 | 2475 |
| lemons | 900 | 12 | 900 |
| sign | 1600 | 21 | 1575 |
| cups | 12000 | 160 | 12000 |
| bigger_jar | 6000 | 80 | 6000 |
| slot | 9000 | 120 | 9000 |
| map_case | 15000 | 200 | 15000 |
| glasses | 20000 | 270 | 20250 |
| snack | 1200 | 16 | 1200 |
| naps | 3000 | 40 | 3000 |
| pebbles | 8000 | 110 | 8250 |
| team | 20000 | 270 | 20250 |

`grow` and `max` stay (the sim's tweak "C" grow numbers get applied in the merge, not here).

data/boxes.json, every box: `"price": 50` becomes `"capsules": 50` (starter 50, lucky 250,
tutorial 50). Same number, now in capsules: at the very start (coin_value 1) it's the same 50
coins; when the shop opens (better drops, value about 96 up to 193k) a starter box costs about
5k..10M coins, which is what stops the box flood (pace report point 4). Only the field name
changes in each box entry, so B1's tier rewrite merges by renaming one key.

Both `_note`s get a line: "'capsules': the price in the machine's plain capsules (x
Machine.coin_value, like the pay), so prices keep up with the machine".

## Code (small, one price function each)

- scripts/idle/jobs.gd: `static func tool_base(tool, value := 1.0) -> float` (capsules x value,
  else coins) and `tool_cost(tool, have, n := 1, value := 1.0)` uses it.
- scripts/game_state.gd:
  - `capsule_value() -> float` = Machine.coin_value(machine, catalog) (job_boost uses it too).
  - `errand_tool_plan`: the "max" loop and the cost use `Jobs.tool_base(tool, capsule_value())`
    (no more reading tool.coins inline).
  - `box_price(box_id, count)`: the ONE box price function:
    `maxi(1, roundi(capsules x capsule_value())) x count` (fallback `price`), capped.
    buy_boxes, coins_short, next_pet_box (piggy bank) already go through it.
- scripts/ui/boxes_tab.gd: the price chip shows `UiTheme.num(GameState.box_price(box.id))`
  instead of the raw `box.price`, and is refreshed in the offers refresh (the machine can change
  while the tab is open); "need N more" / "N coins" / tooltip use UiTheme.num (big prices stay
  short, no spill).
- tools/balance.gd: reads the starter box's capsules ("a box costs 50 capsules").
- errand_tools_view.gd needs nothing (already shows plan[1] with UiTheme.num).

## Save

None. Prices are computed, not saved.

## UI sketch

Nothing new. Same pegboard card ("buy it for 1.2k") and same boxes row (coin chip, buy button);
only the numbers grow as the machine grows.

## Tests (tests/test_core.gd, `_test_prices`)

- Every errand tool has "capsules" (> 0) and no "coins"; every box has "capsules" (> 0).
- Jobs.tool_cost with capsules scales with the value (value 10 costs 10x value 1); a "coins"
  tool (a spot) ignores the value.
- GameState on a fresh machine vs one with tape + oil + flap (coin_value 1 vs 8): the noses
  price and box_price("starter") are both 8x, box_price(.., 10) = 10 x one box.
- At value 75 every tool costs within 10% of its old coin price (table above), so early game is
  the same.
- Huge value (all coin nodes maxed) never goes negative (the cap).

## Flows

- New tests/flows/prices.flow: from rich, view full, tab boxes, expect text "50", shot
  boxes_start; `fix tape` (value 2), tab home, tab boxes, expect text "100", click "10",
  expect text "1,000 coins", expect fits, shot boxes_fixed.
- Run and look at the shots: fits, errands, errand_tools, errand_jobs, boxes, prices.
  (errand_tools fixes tape/oil/flap = value 8, so its pegboard shows smaller prices than today;
  its coins steps are big enough either way.)
- Checks: test_core.gd and balance.gd with --profile=test-prices; machine_pace.gd unchanged
  (it doesn't price tools or boxes).

## Done-notes

docs/plans/PRICES-done.md with the text for docs/design.md, docs/architecture.md, the dev plan
and CLAUDE.md, plus no save bump.

## Questions for Emilia (picks until answered)

1. Boxes: I kept the number (starter 50 capsules), so a box costs 50 capsules' worth; when the
   shop opens that's roughly 5k-10M coins instead of 50. Too steep or right? (The pick said it
   should stop the box flood; a lower base like 5 capsules is an easy data change.)
2. Errand tools use "75 capsules = today's price" (the value when errands open). Tools that open
   later (jar, scouting, cups, pebbles, team) get pricier than today at their opening, since the
   machine has grown by then. That's the point of the pick, but say if one feels off.
