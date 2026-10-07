# X2 GameState split: done

## What was built

`scripts/game_state.gd` was 7068 lines. Its code now lives in 21 parts under `scripts/state/`, one
per area. GameState itself is about 500 lines of state plus about 490 one-line forwarders.

- **GameState keeps:** every var, signal and const, `_init` (the signal wiring), `_process`,
  `_notification`, `tool_run`, and the statics (`box_cost`, `water_fill`, `school_face`,
  `coins_int`, `_without`). It also keeps a forwarder for every part function that is public or that
  something outside its part calls. Example:
  `func pull_lever() -> Dictionary: return machine_part.pull_lever()`.
  So `GameState.<name>()`, `gs.<name>()` in the tests and tools, `GameState.<var>` and the signals
  all work as before.
- **game_state.gd has a class_name now:** `GameStateNode`. The name `GameState` is the autoload's,
  so the class needs another one. The parts use it as a type: `var gs: GameStateNode`.
- **A part** is a `RefCounted` that GameState makes, e.g. `var machine_part := MachinePart.new(self)`
  in the block between "GameState's parts" and "end of the parts". It reaches the state through `gs`
  (`gs.coins`, `gs.changed.emit()`, `gs.save_game()`) and the consts and statics through the class
  (`GameStateNode.SAVE_VERSION`, `GameStateNode.coins_int(...)`). Inside a part, its own functions
  are called directly.
- **Vars did not move.** Every var stays on GameState, private caches included. The save, the UI, the
  tests and DevDriver read them there. That kept the move a pure code move, and other lanes' code
  that touches vars still fits.
- **`tools/state_parts.py`:**
  - `move <stem> <Class> <var> <funcs...>`: cuts functions (with their `##` docs) out of
    game_state.gd and rewrites them for the part. A bare GameState var, signal or function becomes
    `gs.<name>`, a const or static becomes `GameStateNode.<NAME>`, and locals in scope stay as they
    are. It adds the part to the registry and writes the forwarders again.
  - `forwarders`: writes the forwarder block again.
  - `check`: every `gs.X` / `GameStateNode.X` in the parts, and every `GameState.X` / `gs.X` in
    scripts, tests and tools, names something GameState has. Godot does not flag an unknown member
    on a typed script instance until that line runs, so this check is needed.
  - `names <func>`: tells which part has a function.
- **Docs:** docs/architecture.md has a new section, "GameState and its parts". The dev-plan X2 entry
  says done.

## Areas: what moved where

- `adventures_part.gd` (AdventuresPart): debug_give_parts away sendable_pets _sendable_stand_ins
  send_on_adventure answer_event collect_run toss_treat treat_every treat_zoom streak_max
  trail_part_x treat_ready_in zooming _zoom_runs trail_pickup keep_trail_part _advance_runs _advance
  debug_finish_runs
- `automation_part.gd` (AutomationPart): auto_jobs knows_job teach_job set_task auto_tool_block
  auto_tool_cost buy_auto_tool auto_party set_auto_party auto_places auto_run _work_automation
  _work_since _release_saves _work_for_automation _auto_adventures _unused _send_auto_party
  _pet_cranks _pet_capsule _crank_context _load_automation
- `boosts_part.gd` (BoostsPart): grant _bit_home grant_wisps boost boost_parts boost_receipt
  _boost_line_name capsule_why errands_why _errands_layered _boosts_changed _knacks_changed
  _knack_gates_changed _knack_counting knack_own knack_gate knacks_of trip_knacks check_book add_xp
- `boxes_part.gd` (BoxesPart): set_job coin_reserve default_reserve reserve_step reserve_max
  set_reserve box_price shop_boxes book_rank box_in_shop stash_boxes box_is_new box_news greet_box
  buy_boxes debug_give_box coins_short open_boxes in_bag boxes_that_fit debug_give_pets
  add_debug_coins _give_first_pet pet_opens save_for_me next_pet_box pet_box_order boxes_on_pile
  can_auto_open pack_job_seen _open_in_background background_packing auto_open_pack _pin is_good_pull
  dismiss_pinned take_idle_log _log_idle newest_box_id
- `care_part.gd` (CarePart): gifts_waiting gifts_open _tick_gifts open_gift debug_set_gifts
  debug_gift_clock snack_price feed pat set_care _check_care _forget_care_boosts _without_care
  rummage_open rummage_ready rummage set_pet_out
- `dungeon_part.gd` (DungeonPart): take_dungeon_news dungeon_open dungeon_running _army_uids _out
  _army_herd army_herd_keys army_power_of army_cards army_choices _strongest_first army
  army_herd_room _working_cards set_army_card army_best set_army_herd army_fill_up army_empty
  _free_for_army _off_work _trim_army_herd _army_changed set_order set_order_to set_start army_rules
  _army_rules floor_words send_army dungeon_floor_now dungeon_left _dungeon_tick _finish_dungeon_run
  _best_bit drop_dungeon_report _home_again _run_losses hold_spots hold_can_go hold_room hold_faces
  send_holders _army_while_away _dungeon_first
- `edge_part.gd` (EdgePart): edge_open edge_torn edge_to_go edge_done resting_shelves
  send_past_edge _open_edge_pages school_open seat_in_school class_full ring_bell school_boost
  school_changed_boost pets_a_minute
- `errands_part.gd` (ErrandsPart): _work_jobs _work_for scout_hold scout_full set_scout_notes
  open_jobs _crew_sum job_crew job_herd job_size job_faces _job_state job_of job_fill job_fill_now
  job_rate _job_errands_x _job_plain_rate _job_tool_numbers _kitchen_changed kitchen_bonus
  capsule_value job_boost job_tips errands_per_minute errands_per_minute_with job_rate_with
  set_errand_tool_level _tools_changed errands_away_hours job_level errand_tool_level
  errand_tool_block errand_tool_plan buy_errand_tool put_on_job take_off_job _moved_name share_out
  set_job_join job_joins _auto_place _take_off _speed_of _pet_speed _crews_changed
- `gear_part.gd` (GearPart): gear_level shown_gear gear_block gear_price buy_gear set_gear_level
  gear_page_open trip_gear _boost_trip_loot _coin_gear_name
- `homes_part.gd` (HomesPart): room_cap room_left room_is_full room_is_cozy room_price
  room_currency room_next room_split room_shown buy_room wisps_shown _room_hit homes_open spare_pick
  _spare_ctx keep_line may_go_finish spare_shelves _spare_changed homes_can_go spare_face _take_spare
  send_home _sorter _sort_pet _flush_school rule_destinations sorted_today set_rule rule_rarities
  rule_finishes keep_lines_on keep_line_count keep_lines keep_line_options set_keep_line kept_count
  _keep_new _keep_lines_changed
- `machine_part.gd` (MachinePart): globe_news greet_globe _globe_home pull_lever _pet_box_due
  _capsule machine_odds _machine_prize _tutorial_pet_due machine_upgrades _machine_gives
  capsule_seconds bit_hint fever_left buy_machine_upgrade
- `perks_part.gd` (PerksPart): perk_level perks_shown perk_price perk_available perks_affordable
  perk_carrot buy_perk debug_perk _perks_changed perk_count front_row_size perk_holds perk_nudges
  perk_away_hours
- `plushie_part.gd` (PlushiePart): plushie_open _plushie_keeper_uid plushie_keepers plushie_keeper
  plushie_can_swap plushie_swap plushie_herd _plushie_keys plushie_feed_herd plushie_cards
  plushie_has_cards _plushie_card_ok plushie_feed_card plushie_spin plushie_bank plushie_hold
  plushie_nudge plushie_price plushie_buy plushie_wild_step plushie_odds _plushie_sewn _plushie_saved
- `rest_part.gd` (RestPart): _resting _rest_changed _herd_used _stand_ins_out resting_cards
  resting_herd resting_count resting_faces resting_pets _resting_stand_ins spare_count _faces
  herd_faces shelf_split _busy_uids _on_folded _pick set_worker_join worker_joins set_join_up_to
  any_join _place_new _herd_at_places _herd_off_places
- `save_part.gd` (SavePart): debug_new_game save_game _finish_save load_game _load_save
  _clamp_herd_places _regate _migrate
- `sewing_part.gd` (SewingPart): sewing_open sew_room sew_front sew_can_sit _sew_gone sew_pickable
  sew_pick_room sew_seat sew_unseat _sew_fill sew_seat_pets _sew_seated_pets sew_seated sew_marks
  sew_party _cap_keys sew_can_go sew_word send_to_room _finish_room_run sew_hint _best_box debug_sewn
- `toys_part.gd` (ToysPart): _finish_plays toy_again play_toy fix_toy combine_toy sacrifice_toy
  sacrifice_toys combine_toy_all shine_toy sew_part (grafting goes here: it's the workbench)
- `unlocks_part.gd` (UnlocksPart): is_unlocked unlock location_open page_open feature_on tab_open
  check_unlocks find_events_at _count_find_tries _open_entry open_page _opened _earned
  all_places_open _gift_pet _gift_buttons take_announcement is_open follow_lead _spot_places
  _place_known open_locations next_door_open sent_to visits_at lights_left is_ours ours_shown
  add_visits follow_rumour _hear_rumours max_party debug_unlock_all tutorial_active tutorial_info
  _start_tutorial _check_tutorial debug_lock_all _milestone buyable upgrade_news saw_upgrades
- `wish_part.gd` (WishPart): wish_open set_wish wish_shelves send_to_wish debug_wish
- `workers_part.gd` (WorkersPart): worker_job knows_others worker_jobs teach_others_block
  teach_others_cost teach_others workers_of workers_herd workers_count worker_faces spot_plan
  buy_spots _add_spots _free_party_place party_places open_pages spot_exist spot_room workers_total
  put_workers _add_workers take_off_workers _take_off_workers _workers_changed workers_speed
  _whistle_checks whistle_seen set_whistle_tick step_whistle_keep _workers_open
- `workshop_part.gd` (WorkshopPart): workshop_open workshop_shown built helpers_can_go send_helpers
  build_drawing debug_build _built take_postcard _vane _workshop_chores _ring_bell

## Save version

No bump: still 43. Save, load and migrations moved into `save_part.gd` and are otherwise unchanged.

## How it was checked

- **Each area, after its move:** `python3 tools/state_parts.py check`, then a compile of all ~167
  scripts with the autoloads up (every script loads, none fails), then the core tests (ALL PASSED,
  6117 checks). Each area is its own commit.
- **Pure code move:** every one of the 663 top-level declarations in the old game_state.gd is still
  there. Each moved function, with `gs.` and `GameStateNode.` taken out, is character for character
  the old function. Every forwarder's signature matches the old one exactly.
- **Locals that share a GameState name** (room, sent, army, news, finds, jobs, away, bits in 16
  functions): checked by hand. They stay locals, and only the GameState var in `_load_save` (`bits`)
  is `gs.bits`.
- **Saves:** I took all 6 test saves through load and save with the old and the new code. Same keys
  in the same order. The only differences are clock-dependent values (saved_at, gifts.next_at, errand
  fills), and two runs of the old code differ the same way.
- **The other checks:**
  - The core test log is the same as before, apart from stack-trace file names.
  - `tools/balance.gd` output is byte-identical.
  - The pace sim is not deterministic even on the old code; the new code lands in the same range.
  - The test timings are the same as the old code's under the same machine load.
- **Every flow:** see "Flows" below.

## Flows

Every flow in tests/flows/ passes: all 60, run 4 at a time with `DESK_PETS_SLOW=3`, and no script
errors in any log. They passed on the old code too (13a1126, run the same way). The perf flows
(perf_huge, perf_late, perf_corner) show the same or better frame times; the machine load is the
bigger factor there.

## Merge notes

- **Conflicts:** this lane rewrites almost every line of game_state.gd, so any lane that touched
  game_state.gd will conflict. Two ways through:
  1. **Simplest:** merge the other lanes first and leave x2's game_state.gd and scripts/state/ out.
     Then take `tools/state_parts.py` and run `docs/plans/X2-redo.sh` on the merged game_state.gd.
     That script is the 21 `move` commands with every function name above; on the old file it gives
     the same functions as this lane, which I checked.
     - A function another lane added stays in game_state.gd until you add its name to the right line
       of the script. It works fine either way.
     - Then run `godot --headless --import` (new class names), `python3 tools/state_parts.py check`
       and the tests.
     - The tidy commit is cosmetic and can be skipped or redone by hand. It gathers the consts, vars
       and statics left in the lower half of game_state.gd and adds each part's header line.
  2. **Merge x2 first, then port each lane's game_state.gd changes:**
     - A change inside a moved function goes to that function in its part (list above). Write
       `gs.` before GameState names and `GameStateNode.` before consts.
     - Or paste the function back into game_state.gd and `move` it again.
     - A new function: put it in game_state.gd, then
       `python3 tools/state_parts.py move <stem> <Class> <stem> <name>` moves it into the right part.
     - A new var, signal or const stays in game_state.gd.
     - After any hand edit: `python3 tools/state_parts.py forwarders` and `check`.
- **New class names** (GameStateNode, 21 parts) need `godot --headless --import` once in each
  checkout, or `-s` scripts can't find them.
- **Calls a part makes:** a part calls other parts through `gs.<name>()`, i.e. through GameState's
  forwarders. That keeps every function reachable by its old name. A private function gets a
  forwarder only while something outside its part calls it, so if new code calls a private
  `GameState._x()` that has none, `check` reports it; then run `forwarders` again.
- **Flaky test:** "v21 and v2x saves load the same" failed twice while the machine was very busy
  (load average 70). It is the known flaky one in CLAUDE.md, and 12 runs in a row afterwards passed.
  It compares saves made a moment apart, and its clock-dependent fields can cross a boundary.

## Questions for Emilia

None. This is a pure refactor and nothing in the game changes.
