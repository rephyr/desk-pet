# PRICES: done

Errand tools and boxes are priced in capsules. Their coin price is the base in capsules times
`Machine.coin_value` (the same unit errand pay uses, with no toy boost), times grow^level for tools.
The UI still shows coins.

## Built

- **data/errands.json:** every tool's `"coins"` is now `"capsules"`, set to the old price / 75 so
  prices stay the same at a capsule worth 75 coins (about when the basket opens):
  - noses 2.5, paws 5, pockets 33
  - lemons 12, sign 21, cups 160
  - bigger_jar 80, slot 120
  - map_case 200, glasses 270
  - snack 16, naps 40, pebbles 110, team 270

  `grow` and `max` did not change. The `_note` explains `capsules`.
- **data/boxes.json:** every box's `"price"` is now `"capsules"` with the same number (starter 50,
  lucky 250, tutorial 50). The `_note` explains it. This is one key per box, so the B1 tier
  rewrite only needs to rename `price` to `capsules` in its new boxes.
- **scripts/idle/jobs.gd:**
  - `tool_base(tool, value := 1.0)` returns capsules × value, or the fixed `coins`.
  - `tool_cost(tool, have, n, value := 1.0)` uses it. The result is at least 1 coin when n > 0,
    0 for n = 0, and capped at MAX_PRICE.
  - Automation spots and tools still carry `coins`, so they keep fixed prices.
- **scripts/game_state.gd:**
  - `capsule_value()` (= Machine.coin_value). `job_boost` uses it.
  - `errand_tool_plan` passes the value in, and its "max" loop uses `tool_base`.
  - `box_price(id, count)` is the one box price function. It calls the static
    `box_cost(box, value, count)`, which uses capsules × value, falls back to the fixed `price`, and
    is capped. `buy_boxes`, `coins_short`, `next_pet_box` and the pet's opening job already go
    through it. `box_cost` rounds ONE box's price first (at least 1 coin), then multiplies, so
    "buy 10" is always 10x the chip even when a capsule is worth a fraction.
  - Your pet's box reserve ("keep at least") is in capsules too: `reserve_capsules` (was
    `coin_reserve` in coins), `coin_reserve()` = reserve_capsules x capsule_value(), used by
    `next_pet_box`. `default_reserve()` / `reserve_step()` / `reserve_max()` read boxes.json
    `"reserve": { "capsules": 50, "step": 50, "max": 2000 }`; `set_reserve(n)` clamps and saves.
- **scripts/core/catalog.gd:** `box_rules` = the whole boxes.json (for `reserve`).
- **scripts/ui/boxes_tab.gd / settings_tab.gd:** the "keep at least" stepper and the settings
  slider move in capsules (step and top from data) and show coins with `UiTheme.num`
  (RESERVE_STEP const removed). At the start (capsule = 1 coin) they look exactly as before.
- **scripts/dev/dev_driver.gd:** new step `reserve <n>` (your pet keeps n capsules); in
  `expect text "..."` / `click "..."`, `\n` matches a line break (two-line buttons like
  "buy it\nfor 20").
- **scripts/ui/boxes_tab.gd:**
  - The price chip shows `UiTheme.num(box_price)`.
  - `_refresh` updates the chip, because the machine can grow while the tab is open.
  - "need N more", "N coins" and the tooltip use `UiTheme.num` (for example "need 40.2M more").
- **tools/balance.gd:** reads the starter box's `capsules` (the price at the start).
- **tests/test_core.gd:** `_test_prices` (58 checks):
  - every tool and box is priced in capsules
  - prices scale with the value, and fixed-coin spots and boxes ignore it
  - on a fresh machine vs tape + oil + flap (value 1 vs 8), prices are 8×, and 10 boxes cost 10×
    one box, also at a fractional value (74.3)
  - the reserve has a start, step and top in data
  - every tool is within 10% of its old price at value 75
  - with every machine node owned, no price goes negative
- **tests/flows/prices.flow (new):** runs from the rich save:
  1. The buy buttons show "50 coins" / "250 coins" (not the quick chip "50").
  2. After `fix tape` they show "100 coins" / "500 coins", and "10" shows "1,000 coins".
  3. After oil and flap, find the basket: click the noses tag, its card says "buy it\nfor 20".
  4. `fix shine 10`, `heavy 3`, `plate 3` (a capsule worth about 16k): the pegboard shows 40.2k etc.
     The boxes show 805k / 4M, and x50 shows "need 40.2M more".
  5. `teach boxes`, `reserve 7`, `unlock feature:shopping`: "keep at least" shows 113k
     (7 capsules at about 16k, a number no price on screen shows).
  6. `expect fits` runs throughout.

## Save

**Bump: SAVE_VERSION 23 -> 24** (renumber at merge). The field `coin_reserve` (coins) is replaced
by `reserve_capsules`. `_migrate` (version < 24) converts: capsules = round(old coins /
Machine.coin_value of that save's machine.bought), at least 1 if it kept any, 0 stays 0; then
erases `coin_reserve`. Checked with a temporary v23 save (8000 coins kept, tape + oil + flap =
value 8): it loaded as 1000 capsules and showed "8,000". The test saves (v12, no machine, 50)
load as 50 capsules. Prices themselves are computed, not saved.

## Checks run

- test_core: ALL PASSED (3399 checks)
- balance.gd: runs
- Flows that passed, with screenshots checked: prices, fits (after the reserve fix; errands,
  errand_tools, errand_jobs and boxes passed before it and don't touch the reserve).
- tools/play.py (separate commit): the hashed Xvfb display number is now a starting point; it
  skips numbers with a /tmp/.X<n>-lock or /tmp/.X11-unix/X<n>, and retries once on the next free
  number if xvfb-run says "Xvfb failed to start".

## Text to add

**docs/design.md:** already added in two places: "Priced in capsules" under Loot boxes, and a
paragraph on the pegboard.

**docs/architecture.md:** already added to the ErrandsTab line.

**docs/dev-plan.md:** mark the step done:

> PRICES (done): errand tools and boxes priced in capsules (errands.json tool "capsules",
> boxes.json "capsules", x Machine.coin_value via Jobs.tool_cost / GameState.box_price). Early
> prices unchanged (tools match the old coins at a capsule worth 75, boxes at 1); later they keep
> up with the pay. Your pet's box reserve is in capsules too (boxes.json "reserve", save v24
> reserve_capsules). Flow: prices.

**CLAUDE.md "where we left off":**

> - Prices (lane PRICES): errand tools and boxes cost capsules, not coins (data "capsules" x
>   Machine.coin_value = GameState.capsule_value(); Jobs.tool_base/tool_cost(..., value),
>   GameState.box_price -> static box_cost). The UI still shows coins (UiTheme.num). Automation
>   spots keep fixed "coins". The pet's box reserve ("keep at least") is in capsules too
>   (boxes.json "reserve", GameState.reserve_capsules / coin_reserve(), save v24 converts old
>   coin_reserve). Dev step `reserve <n>`; `\n` in flow text matches a line break. Flow: prices.

## Merge notes

- For B1 (box tiers): new boxes use `"capsules"` rather than `"price"`. The `price` fallback still
  works if a box keeps `price`, but `_test_prices` expects every box to have `capsules`.
- The A1 sim's tweak "C" for tool prices was not applied here (see the plan).

## Questions for Emilia

0. The pet's reserve starts at 50 capsules (one starter box's worth) and tops out at 2000 capsules
   (40 starter boxes). Fine, or would "boxes kept" read better than a coin number?

1. When the shop opens (better drops), a starter box costs 50 capsules, which is about 5k to 10M
   coins instead of 50. Is that too steep? A smaller base is a one-line change in boxes.json.
2. Tools that open later (jar, scouting, cups, pebbles, team) cost more than before when they
   first appear, because the machine has grown by then. That is what the pick asked for. Does any
   of them feel off?
