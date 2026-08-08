# PLAN.md

Work is organized in milestones. Rules of the game: see
[AGENTS.md](AGENTS.md) (test-first, plan each milestone, resolve open
questions before coding, exit criteria per milestone).

Status legend:

- `[ ]` not started
- `[~]` in progress
- `[x]` done

---

## Requirements

A Sudoku puzzle game for e-ink readers (KOReader plugin, target: Kobo).

- **E-ink friendly UI**: crisp high-contrast grid, no animations, night-mode
  safe, touch-first input (target: Kobo Aura One class screens).
- **Puzzle creation with difficulty levels** based on human solver
  strategies, not brute-force metrics.
- **Hint system**: incremental, human-readable hints ("there is a naked
  double in row 3", "skyscraper on 5"), with progressive reveal.
- **Statistics**: e.g., time per difficulty level, most missed strategies.

## Design decisions (resolved)

1. **Core library**: port of
   [rustoku](https://github.com/huangsam/rustoku) (MIT, pinned commit — see
   README) to pure Lua. All 17 human techniques in scope (incl. Expert/AIC).
   Rust `bitflags` → LuaJIT `bit`; `rand` → injected pure-Lua PRNG; `rayon`
   dropped (single-threaded; `solve_until(2)` is enough for generation).
2. **Divergence from rustoku**: solve steps additionally record *pattern
   metadata* (the cells forming a naked pair, skyscraper base/roof, etc.) so
   hints can name and highlight patterns. Keep this documented here.
3. **Difficulty model**: difficulty of a puzzle = hardest technique required
   in its human solve path (rustoku's model): Easy / Medium / Hard / Expert.
4. **Hint behavior**: progressive reveal — ① technique name → ② pattern cells
   highlighted → ③ apply the elimination/placement. A hint requested means
   the user missed that strategy; count it in stats.
5. **Mistake handling**: entries are only marked live when they violate the
   core sudoku rules (duplicate of 1–9 in row, column, or 3×3 box); anything
   else is accepted silently. A separate "Check board" UI action compares
   against the solution and reveals *all* wrong numbers, including
   rule-legal ones. Stats: live "mistakes" = rule-violating entries; errors
   revealed by check are a separate counter.
6. **Timer**: counts active play time only (pauses in menus / on suspend).
7. **Streak**: consecutive solved games without using a hint.
8. **v1 UI difficulties**: Easy, Medium, Hard, Expert. M7 divergence: the
   original "Expert puzzles behind a setting" gate was dropped — Expert is
   always offered in the picker (AIC hints have been solid since M4); the
   synchronous generation wait is mitigated by a "Generating…"
   notification.
9. **Stats storage**: JSON files in KOReader's data dir (`sudoku_stats`,
   `sudoku_save`). M5 divergence from the original "via persist.lua" wording:
   persist.lua has no JSON codec (serpent/dump/bitser only), so the JSON
   codec is a small pure-Lua module (`json.lua`) and `storage.lua` writes
   plain files with injected paths. Time stats count finished games;
   give-ups are recorded separately.
10. **Test location**: specs live in `tests/unit/` (versioned) and are
    symlinked into the gitignored koreader checkout's `spec/unit/` by the
    dev setup.

## Architecture

```
sudoku.koplugin/
├── _meta.lua, main.lua          # plugin entry + Tools menu (exists)
├── core/                        # PURE Lua — zero KOReader deps, unit-testable headless
│   ├── sudoku.lua               # public API facade
│   ├── board.lua                # 81-cell grid, parse/serialize, validation
│   ├── masks.lua                # row/col/box constraint bitmasks
│   ├── candidates.lua           # per-cell candidate bitmasks
│   ├── solver.lua               # MRV backtracking (solve_any / solve_until / solve_all)
│   ├── solve_path.lua           # SolveStep/SolvePath w/ technique + PATTERN metadata
│   ├── techniques/
│   │   ├── flags.lua            # technique bitflags + difficulty tiers
│   │   ├── units.lua            # row/col/box cell lists
│   │   ├── propagator.lua       # deterministic technique loop (mediator)
│   │   └── <17 technique files> # naked/hidden singles/pairs/triples/quads,
│   │                            # locked candidates, X-Wing, Swordfish, Jellyfish,
│   │                            # Skyscraper, W-Wing, XY-Wing, XYZ-Wing, AIC
│   ├── generator.lua            # unique-solution + symmetry + difficulty-targeted
│   └── hints.lua                # progressive hint derivation + missed-strategy classification
├── game.lua                     # game state machine: board, notes, undo/redo,
│                                # timer, mistake/check layers, win detection (pure, time-injected)
├── stats.lua                    # stat recording/aggregation (pure)
├── json.lua                     # minimal strict JSON codec (pure)
├── storage.lua                  # JSON file save/load/delete (injected paths)
└── ui/                          # sudokuview.lua (grid render + input), numberbar.lua, statsview.lua
tests/unit/*_spec.lua            # busted specs (symlinked into koreader spec/unit)
third_party/rustoku              # pinned rustoku clone (gitignored reference)
```

Determinism: `core/` never calls `os.time()` / `math.random`; PRNG seed and
time are injected.

## Milestones

### M0 — Repo hygiene & test harness

- [x] Initial commit of existing skeleton (once harness is green)
- [ ] Verify actual test invocation (`kodev test` meson vs `--busted`)
- [ ] `tests/unit/` + symlink into koreader `spec/unit/` + smoke spec
- [ ] Fix README: test path (`spec/unit`, not `spec/front/unit`), structure
- [ ] Pin rustoku reference (clone `third_party/rustoku`, record commit in README)

**Exit criteria**: smoke spec runs green via the documented command; README
accurate; luacheck clean; initial commit.

### M1 — Core foundations (fully tested)

Refined plan (design decisions: plain functions + data tables; errors as
`nil, message`; board = flat 81-array, candidates = 9×9 cache; coordinates
0-based, rustoku parity; **data tables are 1-based, coordinates are 0-based
and converted at accessor boundaries** (board flat 1-based, masks/candidates
`[x + 1]`); LuaJIT `bit` for masks; state tables carry methods via
metatable).

- [x] `core/prng.lua` — xorshift32; `new(seed)` (fixed default, no
      `os.time`/`math.random`), `:next()`, `:int(n)`, `:shuffle(list)`
- [x] `core/board.lua` — `new` / `from_string` (81 chars, `0-9 . _`) /
      `to_string` / `get` / `set` / `clone` / `is_empty` / `count_clues` /
      `iter_empty_cells`
- [x] `core/masks.lua` — row/col/box u16 bitmasks; `new`, `get_box_idx`,
      `add_number`, `remove_number`, `is_safe`,
      `compute_candidates_mask_for_cell`
- [x] `core/candidates.lua` — 9×9 u16 cache; `get`/`set`/`get_candidates`,
      `update_affected_cells`/`_for` (placed-number optimization), `count`
- [x] `core/solve_path.lua` — SolveStep-shaped steps (`type`, `row`, `col`,
      `value`, `flags`, `step_number`, `candidates_eliminated`,
      `related_cell_count`, `difficulty_point`); pattern metadata added in M2
- [x] `core/solver.lua` — `new(board, opts)` clones the board, detects
      duplicate values, injects rng; `solve_until(bound)` (DFS + MRV via
      candidate counts, rng-shuffled candidates, path recording),
      `solve_any`, `solve_all` (= `solve_until(0)`; rustoku's rayon split is
      not ported), count-only `count_solutions(limit)`, `is_solved`;
      technique-phase hook point reserved for M2
- [x] `core/sudoku.lua` — minimal facade (`from_string`, `solve_any`,
      `solve_all(limit)`, count-only `solutions_count(limit)`, `is_solved`)
- [x] Specs `sudoku_{prng,board,masks,candidates,solver}_spec.lua` — port
      rustoku's tests (board.rs, masks.rs, candidates.rs, mod.rs core: known
      puzzle→solution, unsolvable, `solve_until` bound semantics, 1/2/6
      solutions, `is_solved`, duplicate detection, determinism). Require
      path: `plugins/sudoku.koplugin/?.lua` relative to the test CWD
      (dev.sh symlinks the plugin into the build dir).

**Exit criteria**: all specs green via `./dev.sh test`, lint clean, PLAN.md
+ README updated, commit.

### M2 — Techniques (port per tier, test-first each)

Refined plan: rustoku **parity for propagation** — the technique fixpoint
runs once at solve start (`solve_until`), then plain backtracking with
empty-flag placements; a puzzle needing techniques mid-solve is classified
"requires guessing" (M3 semantics). `solve_all` = `solve_until(0)` (unchanged,
rayon not ported). Divergence (design decision #2) stays: every technique
step carries `pattern` metadata — generic shape `{ kind, cells, values,
unit? }` plus per-technique extras (skyscraper base/roof, wing pivot/pincers,
fish base/cover, AIC chain nodes); elimination steps from one pattern share
the pattern table. Shared helpers (`sees`, `peers_of`, `bivalue_cells`)
consolidated into `units.lua` (small factoring over rustoku's per-file
duplication).

- [x] M2a Easy: scaffolding (`techniques/flags.lua` — bitflags, tiers,
      difficulty, bit helpers; `techniques/units.lua` — row/col/box cells,
      `find_units_with_n_candidates`; `techniques/propagator.lua` — mediator,
      fixed technique order, restart-on-change, dead-end rollback;
      `solve_path.lua` pattern field; solver `opts.techniques` hook) +
      naked singles, hidden singles
- [x] M2b Medium: naked/hidden pairs, locked candidates, naked/hidden triples
      (HoDoKu n201, h201, lc101, l302, h301; all five example puzzles solve
      guess-free with the seven implemented techniques)
- [x] M2c Hard: X-Wing, naked/hidden quads, Swordfish, Jellyfish, Skyscraper
      (HoDoKu bf201, bf301, bf401, sk01, n401, h401; all six solve guess-free
      with the thirteen implemented techniques). Divergence from rustoku: the
      three fish techniques share one generic engine (`techniques/fish.lua`,
      size 2/3/4) instead of rustoku's per-file duplication; pattern metadata
      for fish records `base`/`cover` line units, for skyscraper `base`/`roof`
      cells.
- [x] M2d Expert: W-Wing, XY-Wing, XYZ-Wing, AIC (HoDoKu w101, y101, z101 plus
      rustoku's x-chain / xy-chain / nice-loop examples; all six solve
      guess-free with the seventeen implemented techniques). Divergences from
      rustoku: AIC nodes are encoded as integers and the BFS is bounded by a
      `MAX_EXPANSIONS` cap and a `MAX_DEPTH` of 14 nodes (rustoku explores
      unbounded; a dense board without eliminations takes multiple seconds
      otherwise) — a capped pass reports `search_capped` and gives up on that
      state, classifying the puzzle as requiring a guess; AIC BFS
      starts are filtered to candidates with a strong link (sound, chains
      always start strong). Wing patterns carry `pivot`/`pincers` (+ W-Wing
      `bridge` cells and `bridge_value`); AIC patterns carry the chain
      `nodes`; `values` always = the eliminated digit(s).

**Exit criteria**: every technique matches its HoDoKu example (eliminations
and placements), whole-puzzle solve paths correct (all six M2c examples solve
guess-free with the thirteen techniques; all six M2d examples solve guess-free
with the seventeen); each technique has its own failing-then-green spec;
parity spec (techniques-enabled `solve_all` ≡ plain solver on the
1/2/6-solution puzzles, the six HoDoKu hard examples, and the six expert
examples, which is what actually exercises the `EASY|MEDIUM|HARD|EXPERT`
tier); determinism with seeded PRNG.

### M3 — Solve path, difficulty, generation

Refined plan: `solve_path.classify(path)` returns the hardest flagged tier,
whether the path contains a flagless backtracking placement, the hardest flag,
and its step number. `generator.generate(opts)` returns a puzzle board or
`nil, message`; it accepts an injected PRNG, samples a solved board, and
removes stable symmetry groups only while preserving uniqueness and the
minimum clue target. Supported symmetry modes match rustoku. Difficulty
targets use rustoku's clue ranges and require an exact no-guessing human solve.

- [x] Difficulty classification: hardest technique used in solve path
- [x] `generator.lua`: solved-board sampling → clue removal preserving unique
      solution (`solve_until(2)`), symmetry modes, difficulty-targeted retry
      loop
- [x] Performance sanity in emulator: generation ≤ a few seconds worst case

**Exit criteria**: property tests — unique solutions; Easy never needs more
than easy techniques; Hard needs (e.g.) skyscraper-level; clue-count ranges;
and the fixed-seed generation benchmark stays below three seconds per sample
on the Kobo Aura One emulator profile.

### M4 — Hint engine (core)

- [x] `hints.lua`: next applicable technique for current board state
- [x] Complete hint result; UI-owned progressive reveal: ① name → ② pattern
      cells → ③ apply
- [x] Missed-strategy classification (hint requested ⇒ technique missed)

The final M4 API is stateless:

```lua
hints.next({
    board = board,
    notes = candidate_masks,
    solution = solution, -- optional; enables solution-candidate validation
    revision = revision,
}, opts)
```

`notes` are authoritative candidate masks, updated by the game layer; empty
cells start with empty notes (an auto-fill setting seeds board-legal
candidates instead — see M5/M6). The core returns one complete deduction
with technique, pattern, action, revision, and stable hint ID; it does not
accept or track a reveal level. The UI owns progressive display of the
technique name, pattern cells, and action. Candidate eliminations already
absent from `notes` are skipped; illegal masks and removal of a known
solution candidate return `note_error` results and block deduction, while an
empty mask is legitimate state (the game layer substitutes board-legal
candidates for untouched cells, and a user-cleared cell is ground truth that
deduction simply cannot use). Notes on given cells are also errors. A
candidate removal that is not the solution value is accepted as user state,
even when the user cannot justify it; callers that need solution-aware
validation must provide `solution`. Without `solution`, deduction and
structural contradiction checks still run, but the engine cannot detect
removal of the correct candidate. Missing or illegal note masks are malformed
state and return an error result.

**Exit criteria**: hints and note-state semantics verified against HoDoKu
examples; complete-result/UI-reveal contract documented; stats feed point
defined.

### M5 — Game state machine + storage (UI-free, testable)

Refined plan: `game.lua` (plugin root, pure, injected `now()`) is the game
state machine; `stats.lua` (pure) aggregates per-game records; `json.lua` +
`storage.lua` persist them as JSON files with injected paths (data-dir
wiring is M6/M7). Resolved decisions: solution comes from
`generator.generate_game` (the solution is already computed during clue
removal); notes auto-clean the placed digit from peers and are pruned to
legal candidates after every move (user removals are never re-added);
mistakes and check-revealed errors are cumulative; stats store per-game
records (capped at 200 each, oldest dropped); storage uses two files
(stats + active save); streak resets on hint-used wins and give-ups;
undo/redo survives save/restore. M6 divergence: notes start **empty** by
default (`autofill_notes` game option seeds board-legal candidates when
on — user-facing setting in the Tools submenu), and erasing a digit
restores the cell's **previous note state** (pruned to candidates still
legal) instead of repopulating all legal candidates; an untouched cell
therefore stays empty through place/erase cycles.

Hint contract: the game passes `solution` to `hints.next`; hints are
blocked while the board has rule conflicts or diverges from the solution
(`nil, "board has conflicts"` / `nil, "board does not match the solution"`)
so deductions are always solution-sound; `note_error` results are surfaced
to the UI; only `"available"` results record the missed strategy (the M4
stats feed point). Hint actions applied via `apply_action` go through the
move machinery and are undoable. M6 divergence: `game:hint()` derives the
notes it hands to the engine — an untouched empty cell (`notes == 0` and
no manual removals) is substituted with its board-legal candidates, while
cells the user has started filling are passed verbatim (ground truth).

- [x] `generator.generate_game(opts)` + facade: `{ board, solution,
      difficulty, clues }`; `generate` unchanged (no caller breakage)
- [x] `game.lua`: givens lock; place/erase (replace supported); note
      toggle/clear with auto-clean; live conflict marking (rule duplicates
      only, derived); mistakes counter; revision counter; undo/redo with
      exact note restoration and redo-stack clearing; timer (pause/resume,
      injected time); `check_for_errors()` (filled cells only, per-cell
      revealed set — counted once until fixed, re-break re-counts);
      `is_won`/`finish`/`give_up` records; `hint()` + `apply_action`;
      `serialize`/`game.restore` with strict validation
- [x] `stats.lua`: per-game records, streak, summary (per-difficulty
      count/avg/best, hints per technique, most-missed with deterministic
      tie-break), `from_table`/`to_table`
- [x] `json.lua` + `storage.lua`: strict JSON (deterministic key order,
      cycle/non-finite rejection, strict decode incl. number syntax),
      file save/load/delete with `nil, msg` errors

**Exit criteria**: state machine + aggregation specs green
(`sudoku_generator_game`, `sudoku_game`, `sudoku_game_serialize`,
`sudoku_stats`, `sudoku_json`, `sudoku_storage`); save/load round-trip
test; `./dev.sh lint` clean; PLAN.md + README updated; commit.

### M6 — Game UI (e-ink first)

Refined plan: UI splits into `ui/layout.lua` (pure geometry with injected
screen size + dp scaler — grid rect, thin/thick borders, font dp sizes, bar
rows, hit-testing), `ui/theme.lua` (luminance-only inks; night mode comes
for free from KOReader's whole-framebuffer inversion), `ui/numberbar.lua`
(paints digit row 1–9+erase and tool row undo/redo/notes/check/menu,
renders centered text), and `ui/sudokuview.lua` (fullscreen
`InputContainer`: paints grid/digits/notes/selection/conflicts/revealed,
tap dispatch, win/give-up/quit flows, stats recording, timer pause on
menus and `Suspend`/`Resume`). Divergences from the original M6 wording
(milestone planning decisions, documented like M2/M5): the **hint button is
deferred to M7** (hint overlay is an M7 deliverable); the **entry point is
minimal** — Tools → Sudoku starts a fresh Easy game directly (difficulty
picker, Continue, and Statistics are M7); **portrait-first layout** (the
grid never overflows in landscape, but landscape is not tuned); quit
auto-saves to `sudoku_save` while give-up/win clear it (Continue lands in
M7); givens use the NotoSans bold variant via `Font.bold_font_variant`.
M6 addendum (post-smoke fixes): digits are **vertically centered** in cells
and buttons (baseline formula fix in `numberbar.render_centered`, covered
by pixel-bbox specs); the Tools entry is now a **submenu** with "New game"
and a checkable **"Auto-fill notes"** toggle (`sudoku_autofill_notes`
reader setting, default off) driving the `autofill_notes` game option; see
the M5 section for the resulting notes/hint semantics (empty notes by
default, erase restores the previous note state, `game:hint()` substitutes
board-legal candidates for untouched cells, empty note masks are no longer
`note_error`).
M6 addendum (playtest round): the selection is now a **bold outline** that
never hides the cell content (no more inverted black cell); pressing a
digit button again **erases** that digit from the selected cell (notes
already toggle); erasing or replacing a digit **no longer re-adds phantom
notes** to peers the user never noted (restoration is driven by the
placement history instead of re-seeding all legal candidates); the timer
is formatted **HH:MM:SS**; closing the view (quit / give up / win) forces
a full **flashui** refresh so no ghosted board remains on the reader
behind it.
M6 addendum (playtest round 2): the selection is an **inverted black cell
with white digits/notes** again (readable both ways); the game timer uses
the **wall clock** (`os.time()`, restart/reboot-proof — the previous
`UIManager:getTime()/1000` fed an fts-encoded value ~10⁶× too large into
`format_time`); the Tools submenu gained a **"Resume game"** entry that is
enabled only while a save exists, and starting a fresh game discards the
old save.

- [x] `ui/layout.lua` + `sudoku_layout_spec.lua` — geometry, hit-testing,
      grid-line positions across 6" (Glo/Clara), 7.8" (Aura One), and
      landscape sizes
- [x] `ui/theme.lua` + `sudoku_theme_spec.lua` — ink table, contrast
      invariants
- [x] `ui/numberbar.lua` + `sudoku_numberbar_spec.lua` — paint-to-BB,
      separators, disabled/active states, notes-mode inversion, vertical
      text centering
- [x] `ui/sudokuview.lua` + `sudoku_view_spec.lua` — paint smoke + pixel
      checks (incl. cell-centered digits), tap dispatch
      (select/place/notes/erase/undo/redo/check), givens lock, win → stats
      record + save cleared, give-up, quit → save round-trip,
      suspend/resume timer pause, pause menu
- [x] `main.lua` wiring — Tools submenu: New game + Auto-fill notes toggle;
      wall-clock-seeded PRNG, stats loaded, view shown
- [x] Emulator smoke check — boots clean with the plugin on
      `kobo-aura-one` and `kobo-clara` (6") profiles, no errors; the
      interactive loop is covered headlessly by `sudoku_view_spec` (the
      checkout has no SDL input replay support for scripted clicks)

**Exit criteria**: specs green (`sudoku_layout`, `sudoku_theme`,
`sudoku_numberbar`, `sudoku_view`), lint clean, emulator boot smoke on both
profiles, PLAN.md + README updated, commit.

### M6.1 — E-ink refresh optimization

Planned: every interaction went through `SudokuView:refresh()` →
`UIManager:setDirty(self, "full")`, i.e. a full-screen flashing refresh on
every tap (cell selection, digit entry, notes, undo…). This milestone limits
both the refresh *mode* and the refresh *region* (KOReader semantics verified
against the pinned checkout: `setDirty(widget, mode, region)` restricts the
EPD update to `region`; `"partial"` is flash-free and gets promoted to a
flashing refresh every `FULL_REFRESH_COUNT` refreshes (default 6, user
setting) for ghosting control; `paintTo` always repaints the whole widget, so
the region only bounds the screen update, not the drawing).

- [x] `game.lua`: pure `mt:affected_cells(r, c, value)` — the set of cells
      whose paint can change when `value` is placed/erased at (r, c): the
      cell itself, peers containing `value` (conflict highlights), peers with
      note `value` (auto-clean), and the last placement's `cleaned` peers
      (notes restored by erase/replace); reuses `each_peer` /
      `last_place_entry` (no new core deps)
- [x] `ui/layout.lua`: pure `layout.cells_region(l, cell_keys)` — bounding
      box of cell rects (`nil` for an empty set)
- [x] `ui/sudokuview.lua`: dirty tracking (`_dirty_cells` set +
      `_dirty_tool_row`, `_painted` flag set by `paintTo`); `refresh()`
      becomes region-limited `"partial"` (tool row as a second small region),
      `"full"` only for the first paint (also requested by `main.lua` via
      `UIManager:show(view, "full")`); cell taps mark old + new selection
      cells; place/erase/note taps mark `game:affected_cells` ∪ selection;
      undo/redo/check and `closeMenu` use a coarse full-screen `"partial"`;
      `onResume`/`onSetDimensions` stay `"full"`; quit/give-up/win stay
      `"flashui"` (via `UIManager:close`)
- [x] Specs: `sudoku_game_spec` (`affected_cells` membership/peers/restored),
      `sudoku_layout_spec` (`cells_region` bounding box + nil), and a
      `UIManager.setDirty` spy in `sudoku_view_spec` asserting modes and
      regions per gesture

**Exit criteria**: specs green, `./dev.sh lint` clean, emulator boot smoke on
`kobo-aura-one` with no errors, PLAN.md + README updated, commit.

### M6.2 — Refresh region refinement (on-device playtest feedback)

Planned: the M6.1 bounding box still flashed large rectangles on device —
moving the selection across the board refreshed the whole rectangle between
the old and new cell, a digit entry refreshed the whole 3×3 box when the
affected peers clustered, and check/undo/redo used a coarse full-screen
partial. Fixed by refreshing **each affected cell individually** (merging
only horizontally adjacent cells in a row into strips, via
`layout.cells_regions`; `cells_region` remains as a bounding-box fallback
when more than `MAX_REGIONS` cells change, e.g. check on a wrecked board),
and by making check and undo/redo precise instead of coarse:

- [x] `ui/layout.lua`: `layout.cells_regions(l, cell_keys)` — one rect per
      cell, horizontal strips for adjacent cells in a row, ordered by
      row/column (spec: empty set, single cell, distant cells separate,
      adjacent cells merged, mixed rows)
- [x] `game.lua`: `mt:undo_affected_cells()` / `mt:redo_affected_cells()` —
      cells an undo/redo of the history entry can repaint (entry cell, peers
      of both involved values for conflict highlights, cleaned/restored note
      peers); specs for place/redo/erase/replace entries
- [x] `ui/sudokuview.lua`: `refresh()` issues one `"partial"` per region
      (capped at `MAX_REGIONS`, then one bounding box); `onCheck` diffs the
      revealed set instead of a coarse refresh; undo/redo mark the entry's
      affected cells; no refresh at all when nothing changed (no full-screen
      partial fallback)
- [x] `sudoku_view_spec`: selection move = two separate cell refreshes,
      digit entry = per-cell regions, undo/redo/check = affected cells only

**Exit criteria**: specs green, `./dev.sh lint` clean, emulator boot smoke on
`kobo-aura-one` with no errors, PLAN.md + README updated, commit.

### M6.3 — One refresh per tap (on-device latency/flicker feedback)

Planned: on device, selection felt laggy and digit entries flickered. Root
cause (verified in the pinned checkout's `ffi/framebuffer_mxcfb.lua`): every
GC16/"partial" refresh waits for the *previous* update to complete, so the
M6.2 per-cell regions (2–4 updates per tap) serialized into ~2×–4× the
latency — and UIManager's periodic promotion of "partial" to a flashing
refresh (~every 5th) ran the full waveform on the UI thread, blocking input
for hundreds of ms and flashing the cell. Fixes:

- [x] `ui/sudokuview.lua`: in-game refreshes use `"ui"` mode — flash-free,
      and never promoted to a flashing refresh by UIManager (so no flicker
      and no UI-thread block); `closeMenu`'s coarse refresh is `"ui"` too
- [x] `ui/layout.lua`: `cells_regions` clusters cells so nearby cells merge
      into one update (cluster bounding boxes stay within a 2×2 cell block),
      keeping scattered cells separate but making a tap a *single* EPD
      update whenever possible (mxcfb serializes consecutive updates)
- [x] `ui/sudokuview.lua`: the tool row only refreshes when the undo/redo
      button state actually flips (`markToolRowIfChanged`), so moves after
      the first no longer pay for an extra update
- [x] Specs: layout cluster tests (2×2 bound, gaps stay separate), view
      mode `"ui"` assertions, tool-row-skip-on-second-move test

Ghosting note: `"ui"` refreshes are never promoted, so there is no periodic
flash to scrub residue; residue stays bounded because every changed cell is
repainted fresh, and first paint / wake / resize / leaving the game still
refresh fully.
M6.3 addendum (on-device readability): notes ink darkened (`COLOR_DARK_GRAY`
→ `COLOR_GRAY_3`) and note font bumped 15→18 dp; bar button fonts bumped
(label 16→20 dp, digits 24→26 dp); contrast/size invariants added to the
theme and layout specs. Second round: board digits bumped (givens 32→38 dp,
entries 28→34 dp) with layout-spec floors (given ≥ 36, user ≥ 32).

**Exit criteria**: specs green, `./dev.sh lint` clean, emulator boot smoke on
`kobo-aura-one` with no errors, PLAN.md + README updated, commit.

### M7 — Menus, hint display, stats screen (done)

Refined plan (milestone planning decisions, documented like M2/M5/M6):
**Expert is always offered** in the difficulty picker (no gating setting —
resolves design decision #8 differently; AIC hints are solid since M4), but
every generation starts with a **"Generating…" notification** (generation,
expert especially, is synchronous and can take seconds on-device). The
**"Resume game" entry is renamed "Continue"** and the menu becomes: Continue,
New game (difficulty submenu Easy/Medium/Hard/Expert), Statistics,
Auto-fill notes. The hint reveal is a strict **three-tap progression**
(① name banner → ② pattern cells highlighted → ③ apply), and any other
interaction cancels the reveal; the action is applied through the move
machinery (undoable) with the revision guard rejecting stale actions. The
hint banner is a **reserved strip** between the grid and the tool row (the
grid only shrinks where vertical space is too tight; portrait layouts are
unaffected). When deduction is blocked because the user cleared a cell's
candidates, the view names those cells (`game:notes_needed()`, pure) instead
of a bare "no hint". The **win dialog** gains "New game" (same difficulty)
and "Statistics" buttons; the statistics screen stays reachable from the
Tools menu only. `format_time` moved to `core/util.lua` (shared by the
views, pure). Hint requests are recorded **per request** (no dedupe): every
"available" result counts as a missed strategy.

- [x] `ui/difficulties.lua` + `sudoku_difficulties_spec.lua` — ordered
      id/label list for the picker and the stats screen
- [x] `core/util.lua` `format_time` + spec (shared HH:MM:SS for the views)
- [x] `game.lua`: `mt:notes_needed()` (empty cells with a non-empty
      `manual_removed` mask) + `sudoku_game_spec` cases
- [x] `ui/layout.lua`: tool row gains the `hint` button (6 buttons); a
      reserved hint banner row sits between grid and tool row; layout-spec
      gaps/banner/portrait-unchanged assertions
- [x] `ui/theme.lua`: `hint_fill` (light ink, distinct from `wrong_fill`)
      + theme-spec invariants
- [x] `main.lua`: Continue / New game → Easy–Expert submenu / Statistics /
      Auto-fill notes; `startGame(difficulty)` with the "Generating…"
      notification; `new_game_cb`/`show_stats_cb` wired to the view;
      `sudoku_menu_spec` updates
- [x] `ui/sudokuview.lua`: three-tap hint reveal (banner, pattern
      highlight, apply), cancel on any other interaction, notes-needed
      message, win dialog with New game/Statistics; `sudoku_view_spec`
      (pixel + refresh-region assertions)
- [x] `ui/statsview.lua` + `sudoku_statsview_spec.lua` — fullscreen report
      of `stats.summary()`: streak, played/finished/given-up, per-difficulty
      count/avg/best, hints per technique (sorted), most missed; tap/Back
      closes
- [x] Emulator smoke check — plugin boots clean on `kobo-aura-one` with no
      errors (the interactive loop is covered headlessly by the view, menu
      and statsview specs; the checkout has no SDL input replay support)

**Exit criteria**: complete loop — generate → play → hints → win → stats —
in the emulator; all specs green, `./dev.sh lint` clean, PLAN.md + README
updated, commit.

M7 addendum (playtest round): the **pause menu** is now a `ButtonDialog`
(Time/Mistakes/**Hints** title; Resume, Statistics, Give up, Quit) instead of
a `MultiConfirmBox` — the old dialog's outside-tap dismissal never called the
cancel callback, so the timer stayed paused after tapping outside; the
`ButtonDialog` `tap_close_callback` fires on outside taps, the Back key and
the Resume button, so the game always resumes exactly once. **Statistics is
reachable from the pause menu** too (shown on top of the still-paused game,
so it returns to the pause menu on close). The Tools-menu Statistics item is
now `keep_menu_open`, so closing the stats page returns to the Sudoku menu
instead of dropping back to the reader. The win dialog also reports the hint
count. `statsview.lua` was reworked into a framed report (bordered card,
centered title, bold section headers with separator rules, clamped to the
frame bottom). Follow-up: the stats page is shown with a `"full"` refresh —
since the Tools menu (and the pause dialog) now stays open underneath
(`keep_menu_open`), nothing else triggers a whole-screen update, so without
it only the tapped menu-row slice reached the display. Follow-up 2: the
stats page fonts were **double-scaled** (`Font:getFace` applies
`Screen:scaleBySize` itself, so passing pre-scaled sizes made the text huge
and pushed long lines out of the frame); the view now passes raw dp sizes,
centers the title, wraps long lines to the frame width, and uses smaller,
more compact sizes.

M7 addendum (feature round): **digit-match highlight** — selecting a cell
that holds a digit highlights every cell showing that digit, either as a
placed value (given or entry) or as a candidate in its notes (`theme.match_fill`,
a mid-gray distinct from hint/error fills; pure `game:digit_cells(value)`).
Tapping the same digit cell again toggles the highlight off, selecting an
empty cell clears it, moves keep the highlight in sync (recomputed after
place/erase/undo/redo/notes), and requesting a hint clears it so the pattern
highlight never clashes.

### M8 — Polish, i18n, deployment

- [ ] gettext-marked strings, settings (e.g., notes on/off)
- [ ] README: deploy instructions, rustoku pin update
- [ ] Kobo on-device smoke test

**Exit criteria**: milestone report, final commit.
