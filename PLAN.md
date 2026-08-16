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
2. **Divergences from rustoku**:
   - Solve steps additionally record *pattern metadata* (the cells forming a naked pair, skyscraper base/roof, etc.) so hints can name and highlight patterns.
   - Propagator technique execution order is structured strictly by ascending difficulty tier (Locked Candidates before Naked Pairs, and Wings/Skyscrapers before Swordfish/Hidden Quads/Jellyfish) so human hints and full solves prioritize simpler techniques over complex subsets/fish.
   - W-Wing parity with rustoku: requires 4 distinct cells ($P_1, P_2, S_1, S_2$) with $P_1 \ne S_1$ and $P_2 \ne S_2$ so that $P_1 = X \implies S_1 \ne X \implies S_2 = X \implies P_2 = Y$ (if a pincer were a bridge end, $P_1 = X \implies S_1 = X$, breaking the conjugate pair deduction).
   Keep these documented here.
3. **Difficulty model**: 6-tier progression (Beginner, Easy, Medium, Hard, Master,
   Expert) determined by peak human technique tier, clue-count thresholding
   (>= 38 clues for Beginner vs < 38 for Easy), and anti-bottleneck step density
   constraints (requiring >= 2 non-trivial steps for Medium through Master).
   Cumulative HoDoKu workload point scoring is tracked on the solve path
   (`classification.score`) as diagnostic metadata.
4. **Hint behavior**: progressive reveal — ① technique name → ② pattern cells
   highlighted → ③ apply the elimination/placement. A hint requested means
   the user missed that strategy; count it in stats.
5. **Mistake handling**: entries are only marked live when they violate the
   core sudoku rules (duplicate of 1–9 in row, column, or 3×3 box); anything
   else is accepted silently. A separate "Check board" UI action compares
   against the solution and reveals *all* wrong numbers, including
   rule-legal ones. Revealed cells keep their gray fill **and the digit is
   struck through with a bar in the digit's ink** (`paint_strike`; inverted
   ink on the cursor cell) so the mark reads as a deliberate pen stroke, not
   a fill change; the strike clears as soon as the cell is fixed. Stats:
   live "mistakes" = rule-violating entries; errors
   revealed by check are a separate counter.
6. **Timer**: counts active play time only (pauses in menus / on suspend).
7. **Streak**: consecutive solved games without using a hint.
8. **UI difficulties**: Beginner, Easy, Medium, Hard, Master, Expert offered
   in the picker with localized labels. The synchronous generation wait is
   mitigated by a "Generating…" notification.
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
│   │   ├── units.lua            # row/col/box cell lists (+ variant units)
│   │   ├── propagator.lua       # deterministic technique loop (mediator)
│   │   └── <17 technique files> # naked/hidden singles/pairs/triples/quads,
│   │                            # locked candidates, X-Wing, Swordfish, Jellyfish,
│   │                            # Skyscraper, W-Wing, XY-Wing, XYZ-Wing, AIC
│   ├── variants/                # variant constraint descriptors (pure, data+logic)
│   │   ├── classic.lua          # no-op descriptor (the default)
│   │   ├── diag.lua             # Sudoku X: the two diagonal units
│   │   ├── killer.lua           # Killer: cage model, combo pruning
│   │   └── killer_puzzles.lua   # M15 predefined puzzle set (6, one per tier)
│   ├── variants.lua             # variant registry (get/list)
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
M3 addendum (RM4): the **medium clue range diverges from rustoku** (25..31,
not 28..34) — measured 2026-08-09, 28..34 boards classify ~90% "easy" and only
~2-6% "medium", forcing dozens of retries and occasional total failure; 25..31
concentrates the medium classifications (~3-13% per attempt). `generate_game`
also records the generation **seed** in its payload (and the game saves it),
so any puzzle can be recreated exactly; see RM4 in `review_plan.md`.

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
highlight never clashes. Fix: the **"Generating…" notification** was scheduled
but never visible — generation runs synchronously on the UI thread, so the
notification could only be drawn on the next UI tick, which never comes before
the generation finishes. `main.lua` now calls `UIManager:forceRePaint()` after
showing it, draining the paint/refresh queues immediately so the wait is
actually announced on screen.

### M7.1 — Number-first entry & long-press mode flip

Planned (UI rework): entry becomes **number-first** — the digit row (1–9, no
Erase button) is a *pen* that stays armed across cells. A resolved behavior
set, agreed with the user before coding:

- **Arming**: tapping a digit arms it (the button inverts, like Notes mode);
  tapping it again disarms, another digit switches. Arming never mutates the
  board. The cursor cell is retained and moves on every tap/hold.
- **Armed highlight**: while a digit is armed, every cell showing it — as a
  value or as a note — is highlighted with `match_fill` (reuses the M7
  digit-match machinery via `game:digit_cells`). The highlight follows moves
  and undo/redo. Requesting a hint clears it (existing "hint clears match"
  rule); the button stays armed.
- **Tap while armed**: empty cell → place; same digit → erase (toggle);
  different digit → replace; given → notification. Notes mode toggles the
  digit as a note.
- **Long press while armed** (`hold` gesture, ~500 ms): flips the mode for
  that one cell — notes off → write/toggle a note, notes on → write/erase a
  value. Long-pressing without an armed digit is a no-op.
- **Cursor fallback**: with nothing armed, cell taps keep the M7 behavior
  exactly (select + digit-match highlight on digit cells).

- [x] `ui/layout.lua`: number row is now 9 buttons (1–9); layout spec updated
- [x] `ui/numberbar.lua`: `erase` label dropped; the armed digit button
      inverts (`state.armed`); numberbar spec covers the inversion
- [x] `ui/sudokuview.lua`: `armed` state + `hold` gesture; number-row dirty
      tracking; `_arm`/`_disarm` (disarm falls back to the cursor match),
      `_applyArmed` shared by tap/hold; `onTap` reworked (no erase branch,
      no "Select a cell first."); `onHold` mode flip; `armed` passed to paint
- [x] `sudoku_view_spec.lua`: interaction tests reworked number-first; new
      tests for arm/highlight, switch, disarm fallback, tap-to-place/toggle,
      long-press note/value flip, no-op without armed, undo-sync, number-row
      refresh region, `hold` gesture in `onSetDimensions`

**Exit criteria**: all sudoku specs green via `./dev.sh test` (the KOReader
`version_spec` failure is a pre-existing `git describe` environment issue,
unrelated), `./dev.sh lint` clean, emulator boot smoke on `kobo-aura-one`
with no errors, PLAN.md updated, commit.

### M7.2 — Hardware key support (digit cycling + notes toggle)

Planned (resolved with the user before coding): the game view gains hardware
key handling so the digit can be selected without the touchscreen. **Digit
cycling**: short presses of any page-turn or directional key
(`PgFwd`/`PgBack`/`Cursor` groups) iterate the armed digit; with nothing
armed the first press arms 1, and cycling always wraps 1→9→1 (no key-based
disarm — tapping the armed digit in the bar stays the disarm path). Arming
reuses the existing `_arm` state machine, so the number-row inversion and
digit-match highlight come for free. **Notes toggle**: a *hold* of a cycling
key (≥ 0.5 s) toggles notes mode, exactly like the Notes button (same
`_toggleNotes` path, so tap and hold cannot drift). Kobo hardware has no
long-press event — only `KeyPress`/`KeyRelease`/`KeyRepeat` — so the hold is
timer-based in the view (`UIManager:scheduleIn`, token-invalidated on the
next press or release). `KeyRepeat` is overridden to a no-op for cycling
keys (the `InputContainer:onKeyRepeat` default is a verbatim copy of
`onKeyPress` and would otherwise auto-cycle while holding); `KeyRelease`
cancels the pending hold. **No settings entry** (user decision): the
bindings exist only while `SudokuView` is the active widget and those keys
are otherwise unused in the game view, so there is no conflict to opt out
of; a toggle can be added later if a real conflict shows up.

- [x] `ui/sudokuview.lua`: `key_events.DigitNext`/`DigitPrev` (PgFwd +
      Down/Right cycle forward, PgBack + Up/Left cycle backward, arming 1
      or 9 respectively and wrapping at the ends; both directions share
      `_cycleDigit`), `onKeyRelease`/`onKeyRepeat` (cycling keys only),
      hold timer with token invalidation, `_toggleNotes` extracted and
      shared with the Notes button
- [x] `sudoku_view_spec.lua` (test-first): press cycles unarmed→1, 1→2,
      9→1 wrap; backward presses arm 9, go 9→8, wrap 1→9; direction
      switching continues from the current digit; cycling marks the number
      row and keeps the digit armed for cell placement (value and note
      paths); KeyRepeat does not advance; KeyRelease before the hold
      elapses cancels it; hold ≥ 0.5 s toggles notes (spied
      `UIManager.scheduleIn` invoked in place of the real clock); a later
      press while held re-arms the timer; both directions schedule the
      notes hold
- [x] Review addendum (2026-08-13): `onDigitNext` is guarded by
      `menu_open`/`is_finished` — modal dialogs (pause menu, win dialog,
      stats page) bind only Back, so unhandled key presses fall through
      the widget stack into the view and would otherwise cycle/toggle
      behind the dialog; the pending hold is also invalidated when the
      pause menu opens and on suspend (key releases are dropped while the
      device sleeps, so the release could never cancel it). Spec: guard
      and invalidation tests, and the `scheduleIn` spy now restores in
      `after_each` instead of only on the success path.
- [x] Review round 2 (2026-08-13): the hold callback itself re-checks
      `menu_open`/`is_finished` (a hold armed just before the winning
      move would otherwise fire behind the win dialog, flip notes and
      re-trigger `onWin` on the finished game — `finish()` then fails
      with "already finished"); `onWin`/`onGiveUp`/`onQuit` invalidate
      the hold too. Hold tracking is now per key (`_holding_key`), so
      pressing/releasing one cycling key cannot cancel the hold of
      another key still held; `onKeyRelease`/`onKeyRepeat` tolerate
      keyless payloads. Spec: multi-key hold, finished-game, win,
      give-up, quit and nil-payload tests. Follow-up: `onKeyRelease`
      guards with `self._holding_key and` — with no key held, a keyless
      release payload would otherwise match `nil == nil` and be consumed
      (and spuriously invalidate the hold).
- [x] Quality-of-life round (2026-08-13): cycling skips digits already
      placed nine times (the greyed-out number-bar buttons,
      `next_cycle_digit` over the view's `_completed_digits`); a press
      from an armed completed digit moves to the next non-completed one,
      and with every digit complete (a full-but-wrong board) cycling
      no-ops. Tap-arming is unchanged (completed digits can still be
      armed by touch). Spec: skip-on-cycle, skip-after-completion and
      all-complete no-op tests.

**Exit criteria**: all sudoku specs green via `./dev.sh test`,
`./dev.sh lint` clean, emulator boot smoke on `kobo-aura-one` with no
errors, PLAN.md updated, commit.

### M8a — Complete localization & i18n (done)

Comprehensive internationalization across all user-facing components of the Sudoku plugin using KOReader's `gettext` conventions, preserving zero-dependency pure Lua discipline for `core/`:

- [x] `ui/techniques.lua`: localized display names for all 17 solving strategies (`techniques.label(id)`).
- [x] `ui/messages.lua`: localized message mapping for pure-engine errors and game notifications (`messages.translate(err)`).
- [x] `ui/difficulties.lua`: dynamic localized resolution of difficulty labels (`difficulties.list()`, `difficulties.label(id)`).
- [x] `ui/sudokuview.lua`: wired localized technique labels in progressive hint banner, error notifications, and `N_` pluralization for wrong-cell checking.
- [x] `ui/statsview.lua` & `ui/gamedetail.lua`: dynamic status labels and translated technique rankings in most-missed strategies.
- [x] `ui/numberbar.lua`: dynamic button labels for tool row.
- [x] `tools/extract_pot.sh` & `./dev.sh pot`: automated extraction tooling generating `sudoku.koplugin/l10n/sudoku.pot` with full catalog coverage (96 messages) and automatic `msgfmt` compilation.
- [x] `l10n/de/sudoku.po` & `sudoku.mo`: complete, idiomatic German translation catalog with automatic runtime loading in `main.lua:init()`.
- [x] `tests/unit/sudoku_l10n_spec.lua`: test-first specs covering technique translations, message mappings, difficulty dynamic evaluation, POT catalog validation, and German MO catalog execution.

**Exit criteria**: all 46 specs green via `./dev.sh test`, `./dev.sh lint` clean (0 warnings / 0 errors), `sudoku.koplugin/l10n/sudoku.pot` and German catalog extracted, compiled, and verified.

### M8b — Deployment, polish, on-device smoke test

- [ ] README: deploy instructions, rustoku pin update
- [ ] Kobo on-device smoke test

**Exit criteria**: milestone report, final commit.

### M9 — Generation performance (done)

Refined plan: profiled 2026-08-10 on the dev Mac (the Kobo Aura One is ≈5-8×
slower, matching the reported multi-second waits). The greedy dig — a full MRV
`solve_until(2)` uniqueness check after *every* clue removal — was 60-85% of
generation time; classification ran all 17 techniques (incl. AIC) on every
attempt even for a medium target; medium/hard difficulty hit rates (~5%) paid
both repeatedly; and no bound on search work let rare pathological boards
stall for seconds. Fixed with six changes, each spec'd:

- **L1 raw board accessors** — `board.raw_get`/`raw_is_empty`/`raw_set`
  (no per-cell type/range validation) replace the validated accessors on the
  internal hot paths (solver recursion, propagator, candidate updates, unit
  scans). The public validated API is unchanged (`sudoku_board_spec`).
- **L2 box-index lookups** — `masks.get_box_idx` and new
  `box_start_row`/`box_start_col` use precomputed tables instead of
  `math.floor(x / 3)` (LuaJIT is Lua 5.1 and has no `//`); inline box math in
  the propagator, AIC and `units.sees` switched to them.
- **P1 count-based uniqueness** — `is_unique` uses `count_solutions(2)`
  instead of `solve_until(2)`: identical verdict, no per-solution board/path
  materialization. Note: P1/P2/P3 change the RNG consumption pattern (the
  dig's count-only search, the classification tier, and the weighted target
  picker all draw the PRNG differently), so same-seed puzzles differ from
  earlier versions; determinism and seed-reproduction (recorded seed → exact
  replay) are preserved and no test pins a specific puzzle. L1/L2 are
  puzzle-stream-stable.
- **P2 tiered classification** — a difficulty target classifies with only the
  technique tiers up to it (medium → `EASY|MEDIUM`, hard →
  `EASY|MEDIUM|HARD`); harder puzzles classify as `requires_guessing` and are
  rejected, never mislabeled. Expert still uses all techniques. The propagator
  runs tiers in fixed order, so in-tier verdicts are identical to an
  all-techniques solve.
- **P3 weighted clue-target sampling** — medium/hard target clue counts are
  sampled by measured per-clue-count difficulty hit rates instead of uniformly
  (medium peaks at 25 clues, 16.7%, hard at 24, 10%; both measured 2026-08-10).
  Weights are hardcoded in `generator.lua`; easy/expert stay uniform.
- **P4 search-work budget** — solver `search_budget` (node cap, default
  `50000` in the generator; normal calls top out ≈13k nodes, the cap never
  fires on the fixed-seed corpus). A capped uniqueness check restores the clue
  (safe side of a rejected removal); a capped classification is a failed
  attempt. Pathological boards now cost a fixed bounded time instead of
  seconds. Divergence from rustoku: its solver searches unbounded.

Measured end-to-end (dev Mac, 20 seeds): medium 0.23 → 0.09 s, hard
0.85 → 0.33 s, expert 0.37 → 0.30 s; `tools/bench_generation.lua` runs well
under its 3 s gate (medium ~20 ms, hard ~20 ms, expert ~160 ms).

**Exit criteria**: all specs green (`./dev.sh test`), `./dev.sh lint` clean,
`tools/bench_generation.lua` passes its `--max-seconds` gate, emulator boot
smoke on `kobo-aura-one` with no errors, PLAN.md + README updated, commit.

### M10 — Stats dashboard & game history

Refined plan (planning decisions, resolved with the user before coding):
`stats.lua` becomes a **v2 game log** (`VERSION = 2`) replacing the two capped
arrays (`finished`, `given_up`) with a single `games` list of per-game entries,
migrating v1 data on load (old records become entries, `status` from `kind`,
`seed`/`board` left nil). A game is logged when it is *started* — the first
`place` or `note`-add commit (`game:is_started()`). Entries:
`{ id, seed, difficulty, status (in_progress|finished|given_up|abandoned),
started_at, ended_at, duration, hints[], mistakes, check_errors, moves, filled,
correct, puzzle, solution, board }`. `puzzle`+`solution`+`board` (81-char
strings each) are stored so the detail page renders the final grid and
"Play again" replays losslessly, independent of generator RNG-consumption
changes; `seed` is kept for provenance. `id` is a fresh numeric key (replay
reuses a seed, so the seed cannot be the identity), assigned by `main.lua`
and threaded through `game.new` → `serialize` → `restore` like `seed`.
`summary()` is computed from the log (single source of truth): totals,
completion rate (`finished/started`) and win rate (`finished/(finished +
given_up)`), total playtime, per-difficulty count/avg/best time + avg mistakes,
current and all-time `best_streak`, ranked `most_missed` techniques,
avg moves/progress. Caps at `MAX_GAMES` (200), oldest dropped but the live
`in_progress` entry is never evicted. In-progress entries are persisted only at
existing save points (`onQuit`, `onSuspend`, pause menu, win/give-up, starting
a new game), never per move; on resume the live entry is matched by `id` and
refreshed from the restored game. Abandoned = a started game replaced by a new
one (finalized in `main.lua:startGame` before the old save is deleted).

UI (native KOReader widgets, agreed with the user): the stats screen becomes a
**dashboard `Menu`** (totals & completion, per-difficulty times, streaks,
mistakes & accuracy, most-missed ranking, plus a "Game history" entry opening
the games list), a **games list `Menu`** (all entries newest-first, rows like
"#41 · Easy · finished · 03:12"), and a **game detail widget** (miniature 9×9
grid reusing `numberbar.render_centered`, givens bold / placed digits regular,
no notes; stats lines; `ButtonRow` with "Play again" — regenerates
`generate_game { seed = record.seed }` and starts it — and Back). Divergence
from the M7 painted `statsview.lua`: that view is replaced by the dashboard
Menu (the custom-painted report is superseded; its tap/Back close and
`sudoku_statsview_spec` coverage move to the dashboard).

- [x] `game.lua`: `game_id` option + serialized field; `mt:is_started()` (set
      on the first `place`/note-add commit); `mt:move_count()`; `mt:progress()`
      (`filled`/`correct`/`clues`); `make_record` extended with `id, seed,
      moves, filled, correct, board/puzzle/solution strings, started_at`;
      `finish`/`give_up` keep returning the enriched record — specs
      (`sudoku_game_spec`, `sudoku_game_serialize_spec`)
- [x] `stats.lua`: v2 log model, lifecycle (`record_started`, `update`,
      `finish`, `give_up`, `abandon`), v1→v2 migration in `from_table`,
      extended `summary` (totals, rates, playtime, per-difficulty incl.
      mistakes, `best_streak`, ranked most-missed), caps with in-progress
      protection — `sudoku_stats_spec` rewritten
- [x] `main.lua`: `game_id` assignment on start/resume, abandon-on-replace in
      `startGame`, `replay_game_cb(seed, difficulty)` wiring — `sudoku_menu_spec`
- [x] `ui/sudokuview.lua`: call `record_started` on first started move; update
      the live entry at save points; finalize on win/give-up; pass replay
      through `main.lua` — `sudoku_view_spec`
- [x] UI: dashboard `Menu` (reworked `statsview.lua`), games list, game detail
      (mini grid + stats + Play again/Back) — `sudoku_statsview_spec` rework +
      new list/detail specs
- [x] README: mention history + replay

**Exit criteria**: all `sudoku_*` specs green via `./dev.sh test`,
`./dev.sh lint` clean, emulator boot smoke on `kobo-aura-one` with no errors,
PLAN.md + README updated, commit.

### M6.4 — One refresh region per interaction (on-device flicker feedback)

On-device feedback: arming/switching a digit made the previously highlighted
cells **flash dark, then white, before the new digit's cells settled gray**.
Root cause: every region update runs a separate EPD waveform (serialized, each
with a visible dark pre-charge phase — the M6.2/M6.3 per-cluster regions
serialize into several sequential flashes per tap). Fix: `refresh()` merges
**all dirty cells into one bounding-box region** (`layout.cells_region`; the
M6.2 per-cluster clustering via `layout.cells_regions` is removed) so an
interaction costs a single cell update plus at most one short bar strip. The
bbox covers only the dirty cells (a cursor move is exactly the two cells), so
the M6.2 "large rectangle between distant cells" problem does not return.

- [x] `ui/sudokuview.lua`: `refresh()` emits one `"ui"` region per frame over
      the dirty-cell bbox; `MAX_REGIONS` and the cluster fallback removed
- [x] `ui/layout.lua`: `cells_regions` (cluster strips) deleted; `cells_region`
      bbox is the only cell-region helper
- [x] `sudoku_view_spec` / `sudoku_layout_spec`: region tests assert the
      single-bbox semantics (selection move, match highlight, armed switch,
      placement, undo/redo, check)

### M6.5 — Fine-grained 6-tier difficulty model and anti-bottleneck puzzle generation

Feedback: difficulty granularity was too coarse (Easy was often trivially solved
in ~1 minute with 1 technique at 38+ clues; Hard often had a single bottleneck
step before collapsing into trivial singles). Fix: expanded to 6 fine-grained
tiers (Beginner, Easy, Medium, Hard, Master, Expert) with HoDoKu-inspired
workload scoring and anti-bottleneck density constraints requiring at least 2
non-trivial steps for Medium through Master.

- [x] `core/techniques/flags.lua`: defined 6-tier composite bitmasks (`BEGINNER`,
      `EASY`, `MEDIUM`, `HARD`, `MASTER`, `EXPERT`), HoDoKu technique point scores
      (`flags.TECHNIQUE_SCORES`), and updated `flags.difficulty` mapping
- [x] `core/util.lua`: `DIFFICULTIES` includes all 6 tiers
- [x] `core/solve_path.lua`: 6-tier ranking (`DIFFICULTY_RANK`), `solve_path.classify`
      computes `non_single_count`, cumulative HoDoKu `score`, and distinguishes
      `beginner` (high clue count >= 38) vs `easy` (< 38) for pure singles paths
- [x] `core/generator.lua`: calibrated clue ranges (`DIFFICULTY_RANGES`), tiered
      techniques, sampling weights, and anti-bottleneck density filtering
      (`meets_density_criteria` requiring >= 2 non-single deductions for Medium through Master)
- [x] `ui/difficulties.lua`: ordered 6-tier list with localized labels
- [x] `stats.lua`, `game.lua`, `main.lua`: validation and menu wiring for all 6 difficulties
- [x] `tests/unit/*_spec.lua`: updated and expanded specs across flags, solve path, generator,
      game payloads, menu, and difficulties; all tests green
- [x] `tools/bench_generation.lua`, `tools/bench_hints.lua`: benchmarked all 6 tiers (<450ms max generation)

### M10.1 — In-game menu enhancements (done)

Added requested features to the in-game pause menu:
- **Difficulty selection on New game**: Tapping "New game" opens a difficulty selection dialog listing all 6 tiers (Beginner, Easy, Medium, Hard, Master, Expert) plus Cancel, starting the generated game at the selected difficulty.
- **Reset puzzle (restart)**: Tapping "Reset puzzle" prompts confirmation ("Reset this puzzle from the beginning? All progress will be lost.") and resets the board to the initial puzzle givens, resets notes (respecting autofill setting), drops pending in-progress stats records for the game ID, assigns a fresh reserved ID, clears errors/mistakes/hints, resets elapsed timer to 0, and clears saves.
- **Fill all notes**: Tapping "Fill all notes" populates all empty cells with their board-legal candidate pencil marks according to current board constraints. Refuses when the board has conflicts or wrong numbers (mirroring hint rules). If notes are already fully populated, it acts as a no-op (no history commit or started flag flip). Otherwise, commits an undoable history step.
- **Confirm on Give up**: Tapping "Give up" prompts confirmation ("Are you sure you want to give up?") before finalizing the forfeit and updating statistics.

- [x] `game.lua`: `VERSION = 2` with v1/v2 restore compatibility; unified `build_notes_grid` builder; `mt:reset()` (reverts board/notes, resets timer to 0, clears mistakes/hints/history); `mt:fill_all_notes()` (bulk legal candidate population with conflict/solution guards and no-op check)
- [x] `stats.lua`: `stats.drop_in_progress(s, id)` to drop abandoned in-progress records upon reset
- [x] `ui/sudokuview.lua`: 2-2-2-1 button dialog layout (Resume/Stats, New game/Reset puzzle, Fill all notes/Give up, Quit), unified `_closeMenuAndResume` execution, `_openDifficultyPicker`, `_confirmReset`, `_confirmGiveUp`, and error notification handling
- [x] `l10n/sudoku.pot`, `l10n/de/sudoku.po`, `sudoku.mo`: extracted and compiled gettext translations for new menu and dialog strings
- [x] `tests/unit/*_spec.lua`: comprehensive specs covering reset, bulk note filling & undo, no-op handling, conflict guards, stats lifecycle, difficulty picker, and confirmation flows

### M10.2 — Post-game menu consistency and statistics navigation (done)

Feedback:
1. The post-game menu and the in-game menu button behaved differently on "New game" (post-game immediately restarted at the same difficulty instead of opening the difficulty picker).
2. Opening statistics from the post-game menu and closing it caused the whole plugin to exit instead of returning to the previous screen.

Changes:
- **ButtonDialog on victory**: Converted post-game dialog from `MultiConfirmBox` to `ButtonDialog` with standard styling, matching the pause menu and difficulty picker.
- **Difficulty selection on win**: Tapping "New game" opens `_openDifficultyPicker`, letting the player choose their difficulty for the next game or Cancel to return to the victory dialog.
- **Persistent view on statistics**: Opening statistics from the post-game dialog keeps `SudokuView` on the stack so dismissing the statistics dashboard returns directly to the game/victory screen.
- **Replay cleanup**: When a replay is started from within statistics, cleanly closes parent dialogs and views before launching the replayed game.
- **Finished board menu wiring**: Tapping the toolbar "Menu" button on a finished puzzle re-opens the post-game dialog (`_showWinDialog`).

- [x] `ui/sudokuview.lua`: Replaced `MultiConfirmBox` with `ButtonDialog` in `_showWinDialog` / `onWin`, wired difficulty picker to victory "New game", preserved view on `showStats`, handled parent dialog cleanup on replay, and routed finished game menu clicks to `_showWinDialog`.
- [x] `tests/unit/sudoku_view_spec.lua`: Expanded specs to verify victory dialog options, difficulty picker launch and cancellation, stats dashboard navigation without view exit, replay cleanup, and finished board menu tap behavior.

### M11 — Code review fixes

Planned (2026-08-15 full-codebase review; existing review md-files ignored as
outdated — all 47 plugin files read, core specs green headless (67/67),
luacheck clean, port parity spot-checked against the pinned rustoku clone):
one confirmed undo/redo data-loss bug (B1), one corrupt-save dead end (B2),
one unvalidated stats field (R4), one W-Wing soundness verification (R1), and dead
code / smell cleanup (S1, S3, S4, S5, S7). Out of scope (future M12): paint
micro-opts (P1–P5), `game.lua`/`sudokuview.lua` module splits (A1/A2),
restore-history semantic validation (R2), ENOENT string matching (R3), AIC
module-level state (R5). Step metrics (`difficulty_point`,
`candidates_eliminated`, `related_cell_count`) stay — they are the
diagnostic metadata of design decision #3.

Findings reference (the review itself is not a repo document; these anchors
are the hand-off for the implementer):

| Code | Symptom | Where |
|------|---------|-------|
| B1 | redo of a replace loses the notes the replace had restored | `game.lua` `redo_entry` place branch (~:788-792); undo mirror `undo_entry` (~:756-762); `place` captures `restored` (~:628-633) |
| B2 | corrupt/edited save makes Continue fail forever, file stays | `main.lua` `continueGame` (:179-202); `storage.load_or_backup` (:83-139) already does backup-on-corruption |
| R1 | W-Wing bridge ends vs pincers (soundness & rustoku parity verification) | `w_wing.lua` `check_pincer_pair` exclusion (:32-34) |
| R4 | `abandon` stores any `ended_at` | `stats.lua` `abandon` (:261-276) |
| S1 | unused ink colors after the dither change | `theme.lua` `hint_fill`/`match_fill` (:14-15); spec asserts at `sudoku_theme_spec.lua` (:16-17, :42-54) |
| S3 | unused APIs | `board.iter_empty_cells` (`board.lua`:121-131); `candidates.restore` (`candidates.lua`:42-48); `candidates.update_affected_cells` wrapper (:100-102), used only by `sudoku_candidates_spec.lua`:159 |
| S4 | `BEGINNER == EASY` mask `0xFF`, split is implicit | `flags.lua` (:26-27); classification splits by clue count in `solve_path.classify` |
| S5 | dead `err or (...)` error paths, reassigned `err` | `generator.lua` (:447, :467, :512) |
| S7 | "solution preserves givens" validated three times | `game.lua` `game.new` (:291-298) and `game.restore` (:1360-1369); `hints.validate_solution` (`hints.lua`:156-176) |

Resolved decisions:

- **B1 fix**: `redo_entry` (`game.lua`) place branch re-adds `entry.restored`
  notes through the same guards `restored_cleaned` uses (empty cell, not
  manually removed, still safe, not already present — i.e. reuse the
  `add_note_digit` checks at `game.lua`:153-159 plus `is_safe_board`),
  mirroring `undo_entry`'s removal — undo→redo must reproduce the exact
  post-place note state. Reproduced today: place 2 (auto-cleans note 2
  from a peer) → place 5 over it (restores that note) → undo → redo loses
  the restored note.
- **B2 behavior**: `continueGame` (`main.lua`) loads the save through
  `storage.load_or_backup` with `game.restore` as the deserializer, so JSON
  corruption *and* semantic validation failure both rename the file to
  `<save>.<ts>.bak` and remove the save. The user sees an InfoMessage
  ("The save was corrupted; a backup was kept at %1") and Continue stays
  disabled until a new game is saved. `load_or_backup` runs the
  deserializer under `pcall` and backs up whenever it returns nil, so
  `game.restore` needs no changes; pass it as
  `function(data) return game.restore(data, { now = os.time }) end`.
  Note: Any restore failure backs up and removes the save (including the
  7-day timer-drift guard and unsupported future save versions), preserving
  the data safely in `.bak` without leaving the UI locked on Continue.
- **R1 resolution (parity with rustoku & mathematical soundness)**:
  W-Wing mathematically requires 4 distinct cells ($P_1, P_2, S_1, S_2$) with
  $P_1 \ne S_1$ and $P_2 \ne S_2$. Proof of unsoundness when $S_1 = P_1$:
  For pincers $P_1 = \{X, Y\}$, $P_2 = \{X, Y\}$ and bridge strong link on $X$
  between $S_1$ and $S_2$, if $P_1 = X$, then $S_1 = X$, forcing $S_2 \ne X$.
  Because $S_2 \ne X$, $P_2$ is NOT forced to $Y$ (it could be $X$ or $Y$).
  In the branch where $P_1 = X$ and $P_2 = X$, *neither* pincer is $Y$, so
  eliminating candidate $Y$ from common peers of $P_1$ and $P_2$ is mathematically
  unsound (and empirically breaks valid solver deduction passes). The exclusion
  `if not p1_is_end and not p2_is_end` is therefore mathematically necessary and
  retained.

- [x] `tests/unit/sudoku_game_spec.lua`: place → replace over it
      (restored note) → undo → redo → notes identical to the post-replace
      state; regression for the current loss (B1). Pattern the test on the
      existing redo spec at `sudoku_game_spec.lua`:488
- [x] `game.lua`: `redo_entry` place branch restores `entry.restored`
      through the `add_note_digit` + `is_safe_board` guards (B1)
- [x] `tests/unit/sudoku_technique_w_wing_spec.lua`: non-vacuous unit test
      verifying W-Wing requires 4 distinct cells ($P_1 \ne S_1, P_2 \ne S_2$)
      to prevent false eliminations, plus HoDoKu w101 metadata checks (R1)
- [x] `core/techniques/w_wing.lua`: preserve sound 4-cell requirement (R1)
- [x] `tests/unit/sudoku_stats_spec.lua`: `stats.abandon` rejects
      nil / negative / non-finite / non-number `ended_at` (R4)
- [x] `stats.lua`: validate `ended_at` in `abandon` — required, number,
      finite, ≥ 0 (mirror `is_optional_finite` at :26-28 but required) (R4)
- [x] `tests/unit/sudoku_menu_spec.lua`: corrupt JSON save → backed up, save gone,
      Continue disabled; semantically invalid save (e.g. invalid board length) → same (B2).
      (`sudoku_storage_spec.lua`:293-326 already verifies `load_or_backup` deserializer handling)
- [x] `main.lua`: `continueGame` via `load_or_backup(game.restore)` +
      corruption InfoMessage formatted with `T(_("... %1"), bak_path)`;
      Continue stays disabled because the save no longer exists (B2)
- [x] Dead code removal (S1, S3): delete `theme.hint_fill`/`match_fill`
      and their `sudoku_theme_spec.lua` assertions (:16-17, :42-54);
      delete `board.iter_empty_cells`, `candidates.restore`, the
      `candidates.update_affected_cells` wrapper; switch
      `sudoku_candidates_spec.lua`:159 to `update_affected_cells_for(c, r,
      col, m, b, nil, trail)`
- [x] `core/board.lua`: shared `solution_preserves_givens(puzzle, solution)`
      used by `game.new` (:291-298), `game.restore` (:1360-1369),
      `hints.validate_solution` (:156-176) (S7) + board spec
- [x] `generator.lua`: replace dead `err or (...)` paths with explicit
      error tracking (:447, :467, :512) (S5); `flags.lua`: comment that
      `BEGINNER` and `EASY` share the same mask with the classification
      split by clue count (:26-27) (S4)

Implementation notes:

- Test-first loop: `./dev.sh test -f <busted-pattern> <spec>` runs one spec
  (or a filtered subset) headless; the full gate is `./dev.sh test`.
- Follow AGENTS.md: one milestone commit, `./dev.sh fmt` before it,
  `./dev.sh lint` gates.

**Exit criteria**: all sudoku specs green via `./dev.sh test`,
`./dev.sh lint` clean, emulator boot smoke on `kobo-aura-one` with no
errors (touches game/main/UI code), PLAN.md updated (M11 + W-Wing
soundness note in design decision #2), commit.

---

## M12: Architecture modularization & code quality refinements ✅

Splits monolithic core and UI files into focused single-responsibility modules,
removes legacy version 1 save/stats compatibility code (pre-public deployment cleanup),
deduplicates shared pure helpers into `core/util.lua`, and completes l10n catalog translations.

### Scope & Architectural Decisions

1. **A1 extraction (`game_serialize.lua`)**:
   - Save serialization (`mt:serialize()`) and strict restoration/history validation
     extracted into `sudoku.koplugin/game_serialize.lua` (pure Lua, zero KOReader deps).
   - Mirrors test structure in `tests/unit/sudoku_game_serialize_spec.lua`.
   - `game.lua` focuses solely on runtime game state transitions and undo/redo stack (~390 lines removed).
2. **A2 extraction (`ui/dialogs.lua`)**:
   - Modal dialogs (win dialog, 2-column difficulty picker, reset/give-up confirmations,
     in-game pause menu) extracted into `sudoku.koplugin/ui/dialogs.lua` (~280 lines removed from `sudokuview.lua`).
   - Note on architectural boundary: `dialogs.lua` is a modal presentation extraction that declutters
     `SudokuView`'s canvas painting and touch/key input loop; it remains coupled to `SudokuView`'s state machine
     rather than an independent headless widget.
3. **Legacy Version 1 Save Format & Stats Cleanup**:
   - Removed `version = 1` save format support (strictly enforcing `version == 2`).
   - Removed `migrate_from_v1` and `recompute_streaks` in `stats.lua`.
   - Cleaned up obsolete v1 migration test cases across test specs.
4. **Helper Deduplication (`core/util.lua`)**:
   - Centralized shared pure helpers (`cell_index`, `validate_cell`, `validate_value`,
     `validate_non_negative`, `new_mask_grid`, `deep_copy`, `constraint_masks_for`, `FULL_CANDIDATE_MASK`)
     into `core/util.lua`, eliminating ~70 lines of duplicate code between `game.lua` and `game_serialize.lua`.
   - Removed dead exports from `game.lua` (`game.serialize`, `game.VERSION`) and fixed tautological test in spec.
5. **Localization & Translation Catalog**:
   - Translated remaining dialog strings in `de/sudoku.po` and compiled to `.mo`.

### Task Checklist

- [x] `sudoku.koplugin/game_serialize.lua`: pure Lua save serialization and restore validation module
- [x] `sudoku.koplugin/game.lua`: delegate `mt:serialize()` and `game.restore()` to `game_serialize`
- [x] `sudoku.koplugin/ui/dialogs.lua`: modal dialog builders and presenters
- [x] `sudoku.koplugin/ui/sudokuview.lua`: delegate dialog presentation to `dialogs.*`
- [x] `sudoku.koplugin/stats.lua`: remove `migrate_from_v1` and `recompute_streaks`
- [x] `sudoku.koplugin/core/util.lua`: shared cell indexing, validation, mask grid, and constraint mask helpers
- [x] `tests/unit/sudoku_util_spec.lua`: comprehensive tests for new `core/util.lua` helpers
- [x] `tests/unit/sudoku_game_serialize_spec.lua`: test `game_serialize` directly, verify v1 rejection, remove tautology
- [x] `tests/unit/sudoku_stats_spec.lua`: verify rejection of v1 stats
- [x] `tests/unit/sudoku_statsview_spec.lua` & `tests/unit/sudoku_menu_spec.lua`: updated test fixtures
- [x] `sudokuplus.koplugin/l10n/`: extract gettext catalog and compile German translations

**Exit criteria**: all 46 test suites green via `./dev.sh test`, `./dev.sh lint` clean (0 warnings / 0 errors),
`./dev.sh fmt` clean, `./dev.sh pot` up to date, PLAN.md and README.md updated.

### M13 — Open-Source Release Preparation (Sudoku+)

Rebrand plugin as **Sudoku+** (`sudokuplus.koplugin`), isolate storage namespaces, set up AGPL-3.0 licensing with rustoku MIT attribution, configure GitHub Actions CI/CD workflows, add community templates, overhaul documentation, and add release packaging tooling.

- [x] Rename root plugin folder to `sudokuplus.koplugin/`
- [x] Update `_meta.lua` (`fullname = _("Sudoku+")`, description)
- [x] Update `main.lua` container name, menu item, save/stats storage paths (`sudokuplus_save`, `sudokuplus_stats`), settings key (`sudokuplus_autofill_notes`), and translation loader
- [x] Update test suites in `tests/unit/*_spec.lua` to reference `plugins/sudokuplus.koplugin`
- [x] Update `dev.sh` and `tools/extract_pot.sh` paths and packaging
- [x] Create `LICENSE` (AGPL-3.0 with rustoku MIT copyright & HoDoKu notices)
- [x] Create release packager script `tools/package_release.sh`
- [x] Create GitHub Actions CI workflow `.github/workflows/ci.yml` (Luacheck + StyLua + Busted)
- [x] Create GitHub Actions Release workflow `.github/workflows/release.yml` with automatic changelog extraction
- [x] Create GitHub release note config `.github/release.yml`, Issue Templates, and PR Template
- [x] Create `CHANGELOG.md` (v1.0.0 initial release)
- [x] Create `CONTRIBUTING.md` (developer & translation guidelines)
- [x] Create `doc/screenshots/README.md`
- [x] Overhaul `README.md` for open-source users & developers

**Exit criteria**: all 46 specs green (`./dev.sh test`), `./dev.sh lint` clean (0 warnings / 0 errors), `./dev.sh pot` up to date, package script creates clean `sudokuplus.koplugin.zip`, documentation complete.

### M13.1 — In-Game & Menu Help Section (How to use it)

Adds a structured, localized Help section explaining game usage, controls, gestures, assistance tools, and difficulty tiers, accessible from both the main KOReader Tools menu and the in-game pause menu:

- **Help module architecture (`ui/help.lua`)**: Modular catalog with 2 focused topics ("How to play & controls", "Features, hints & tools") rendering rich Markdown via native KOReader `Menu` and scrollable `TextViewer` (`text_format = "md"`). Designed for future expansion into solving tactics and strategies.
- **Controls & Input Guide**: Explains Sudoku objectives, number-first pen mode (arm/place/erase/replace/disarm), Notes mode, quick mode-flip long-press gesture (~0.5s), matching digit highlighting, and hardware button shortcuts (page-turn/arrow cycling, completed digit skipping, hold for notes toggle).
- **Features & Tools Guide**: Explains 3-step progressive hints, conflict vs. check-board mistake detection, smart auto-clean, fill all notes, undo/redo, puzzle reset, 6 difficulty tiers (Beginner–Expert), and statistics/history replay.
- **Menu integration**: Added "Help" to the main Tools → Sudoku+ menu (with `keep_menu_open`) and to the in-game pause menu (Row 3 beside "Fill all notes", balancing the pause dialog into 4 rows of 2 buttons).
- **Localization**: Full German translations in `l10n/de/sudokuplus.po` compiled to `.mo` with dynamic runtime translation support.

- [x] `sudokuplus.koplugin/ui/help.lua`: Topic catalog, formatted Markdown getters, `Menu` builder, and `TextViewer` presenter.
- [x] `sudokuplus.koplugin/ui/dialogs.lua`: In-game pause menu updated with Help button on Row 3 and balanced 4×2 grid layout.
- [x] `sudokuplus.koplugin/main.lua`: Main menu registered with Help entry opening help menu.
- [x] `sudokuplus.koplugin/l10n/`: Updated POT template and compiled German translation catalog with 0 fuzzy entries.
- [x] `tests/unit/sudoku_help_spec.lua`: Comprehensive unit tests covering topic definitions, markdown content retrieval, menu construction, and TextViewer invocation.
- [x] `tests/unit/sudoku_menu_spec.lua` & `tests/unit/sudoku_view_spec.lua`: Updated menu and pause dialog tests.

**Exit criteria**: all 47 test suites green via `./dev.sh test`, `./dev.sh lint` clean (0 warnings / 0 errors), `./dev.sh fmt` clean, `./dev.sh pot` up to date.

### M13.2 — Release Polish, Versioning, CI & Attribution

- [x] Embed gameplay screenshot `doc/screenshots/sudoku_plus.png` into `README.md`
- [x] Add "About & Credits" topic to Help viewer with version, author copyright (Boris von Loesch), AGPL-3.0 license, and upstream attributions
- [x] Set `_meta.lua` as the single source of truth for version (`1.0.0`) and name (`sudokuplus`), with automated test assertions
- [x] Make `tools/extract_pot.sh` idempotent (preserving POT timestamps when messages are unchanged)
- [x] Add automated POT and translation freshness validation to GitHub Actions CI workflow
- [x] Full German translation catalog updated and compiled

**Exit criteria**: all 47 test suites green via `./dev.sh test`, `./dev.sh lint` clean (0 warnings / 0 errors), `./dev.sh fmt` clean, `./dev.sh pot` up to date, package script creates clean `sudokuplus.koplugin.zip`.

---

## Variant roadmap (Sudoku X + Killer Sudoku)

Milestones M13–M16 add variant support. (Numbering continues after the existing
M11 code-review fixes and M12 modularization milestones, which are unrelated
to variants.) Both target variants stay 9×9 with digits 1–9, so the board
model, notes grids, undo/redo, stats and hint machinery carry over; the
variant work is about the *constraint model*, which today is hardwired to
row/col/box in `masks.lua`, `solver.validate`, `candidates.lua`,
`units.lua`, `game.lua` mistake marking, `hints.lua`/`game_serialize.lua`
notes legality, and the generator's difficulty model.

### Design decision #11 (resolved with the user) — variant architecture

- A **variant descriptor** (see M13 interface below) is injected through
  solver → candidates → hints → game → generator. `"classic"` is the default;
  every hook is guarded so classic behavior stays byte-identical (guarded by
  the existing parity specs + `tools/bench_*` gates — M9's perf work is at
  risk here and must not regress).
- **Technique topology stays classic**: `units.sees`/`units.each_peer` keep
  their row/col/box semantics for wings/AIC/fish chain validity. Variant
  constraints reach the 17 techniques *through candidate filtering* (sound by
  construction), and variant-specific deductions come from the
  unit-scanning techniques (subsets, locked candidates) once variant units
  are registered in `units.for_each_unit`. A separate
  `each_conflict_peer` hook drives game mistake marking and note auto-clean,
  so the game layer and the solver can never disagree about what a peer is.
- **Difficulty**: all three variants share the same 6 tiers (Beginner–Expert),
  each variant with its own calibration (classic: clue ranges + weights;
  X: re-measured like P3; Killer: cage-structure metrics, M16).
- **Stats are per-variant**: log entries carry `variant` (+ `variant_data`
  for Killer cages); `summary()` gains per-variant sections beside the
  global totals; history rows show the variant.
- **Killer puzzle sourcing**: algorithmic generator (M16), not a puzzle bank.
  M15 ships 6 predefined puzzles purely to make the game playable while the
  generator is built.
- **Killer has no givens**: the board starts empty; the puzzle data *is* the
  cage set. `game.new`'s "at least one given" check and the clue-based
  beginner/easy split in `solve_path.classify` must become variant-aware.
- **Technique selection is per-variant**: a variant may contribute technique
  modules (M16: the killer techniques). The propagator composes its order as
  `classic ∪ variant:techniques()` and the shared flag registry
  (`flags.lua`) stays the single allocation authority — but classic tier
  composites (`EASY`/`MEDIUM`/`ALL`) never include variant bits, so variant
  code can never execute in a classic solve (no perf or behavior leakage, and
  adding a variant cannot shift classic step numbering or hint stability).
  A variant technique's tier lives in the per-variant technique table, not in
  the global `flags.difficulty` branches.
- **Variant boundary (documented ceiling)**: a variant may *add* constraints
  (extra units, candidate refinement, peer sets, full-board rules) but never
  *change* the classic geometry — `masks.lua` box math, `units.sees`/
  `each_peer`, and the fish crossing semantics stay 9×9 row/col/box. Soundness
  of the 17 classic techniques follows from superset peers + candidate
  refinement. Geometry-changing variants (Jigsaw regions, toroidal boards)
  are out of scope; they would need `masks.lua`/`sees` generalization, which
  the hook surface does not provide.
- **Game layer gets stateless legality only**: live mistake marking and note
  legality use `is_safe_extra` + `each_conflict_peer` (peer-local rules);
  stateful variant deductions (killer combos) live in the solver state, which
  is derived purely from `(board, variant_data)` and can be rebuilt by the
  game layer for `legal_mask_for`/autofill. A future variant whose *live*
  violation is non-local (e.g. thermo) must add a game-side state hook.
- **Combined variants are out of scope**: `opts.variant` names exactly one
  descriptor; Killer-X and similar stacks are not planned. The descriptor
  model would in principle compose (unit union, chained state), but no
  composition machinery is built.

### M13 — Variant architecture refactor (foundation, no user-visible change)

Planned: introduce the variant abstraction with `classic` as the only
registered variant. No game-play behavior changes; the variant picker dialog
(Classic only) is the single user-visible addition, and stats gain
data-only per-variant sections (statsview rendering lands in M15). The
milestone is guarded by parity and performance, so M14/M15 can build on it
safely.

**Descriptor interface** (all functions optional; a missing function = no-op):

```lua
{
  name = "classic",                       -- save-format identifier
  -- M14+: extra unit descriptors { type = "diag", index = n } + cell lists
  extra_units = function(self) return { unit, ... } end,
  -- Solver-side state, created per solver instance (and per clone):
  -- derived purely from (board, masks), so clone_state() rebuilds it.
  new_state = function(self, board, masks) return state_or_nil end,
  -- state:filter_candidates(mask, r, c) -> mask     legal-candidate refinement
  -- state:after_place(r, c, num) / state:after_remove(r, c, num)
  -- state:refresh_candidates(candidates, r, c)       recompute affected cells (killer cage)
  is_safe_extra = function(self, r, c, num, board) return bool end,  -- beyond row/col/box
  each_conflict_peer = function(self, r, c, fn) end,  -- mistake-marking/auto-clean peers
  validate_board = function(self, board) return true | nil, err end, -- full-board extra rules
  restore_data = function(self, data) return data_or_nil, err end,   -- variant payload round-trip
  serialize_data = function(self, data) return data end,
  -- M16+: per-variant technique modules { { name, flag, tier }, ... } —
  -- composed by the propagator as `classic ∪ variant:techniques()` (design
  -- decision #11); never run in classic solves
  techniques = function(self) return {} end,
}
```

Registry: `core/variants.lua` (`variants.get(name)`, `variants.list()`)
mapping names to descriptor modules in `core/variants/`.

- [ ] `core/variants/classic.lua` — the no-op descriptor (`new_state` returns
      nil so every hot path skips variant work)
- [ ] `core/variants.lua` — registry + `get`/`list` + spec
      (`tests/unit/sudoku_variants_spec.lua`: get/list, unknown-name error,
      classic no-op behavior)
- [ ] `core/solver.lua`: `solver.new(b, opts)` accepts `opts.variant`
      (descriptor or name; default classic); `solver.validate(b, opts)` gains
      the variant (public call sites in `game.lua`, `game_serialize.lua`,
      `hints.lua` pass it); validate runs `is_safe_extra` per placed digit
      and `validate_board` on full boards; initial candidate computation
      passes through `state:filter_candidates`; `place_number`/
      `remove_number` call `after_place`/`after_remove` +
      `refresh_candidates` (all behind `if variant_state then` guards);
      `clone_state` rebuilds the variant state from the cloned board+masks;
      `is_solved` adds `validate_board`
- [ ] `core/candidates.lua`: `update_affected_cells_for` gains an optional
      trailing `hooks` table (`extra_peers(r,c)` for the subtractive
      placement branch, `refresh_cells(c, r, col, m, b)` for variant recompute).
      Classic call sites unchanged; propagator/solver pass their variant hooks
- [ ] `core/techniques/units.lua`: `for_each_unit(fn, variant)` iterates
      classic units then `variant:extra_units()` cells (cached per variant
      module); `units.sees`/`each_peer` stay classic (design decision #11)
- [ ] `core/techniques/propagator.lua`: `propagator.new` accepts the variant
      descriptor/state; new `prop:for_each_unit(fn)` used by the
      unit-scanning techniques (locked candidates, naked/hidden
      singles/pairs/triples/quads switch their `units.for_each_unit` call
      sites); the technique order composes as `classic ∪
      variant:techniques()` (empty for classic — the M16 plumbing is
      scaffolded now); `count_affected_cells`/`count_candidates_eliminated`
      include `each_conflict_peer` for accurate step metadata
- [ ] `game.lua`: `game.new(options)` accepts `variant` (name; default
      `"classic"`) + `variant_data`; `conflicts_board`/`is_safe_board` scan
      `each_conflict_peer` in addition to `units.each_peer`; `legal_mask_for`
      derives variant-filtered legal masks per call from `(board,
      variant_data)` — the same derivation rule the solver state uses
      (autofill + fill-all-notes); the "at least one given" check becomes
      variant-aware (a variant may allow zero givens — Killer)
- [ ] `core/hints.lua`: `hints.next(state, opts)` accepts the variant;
      notes-legality checks use variant-filtered masks; solution validation
      runs `validate_board`
- [ ] `game_serialize.lua`: `VERSION = 3`; `serialize` writes `variant` +
      `variant_data`; `restore` accepts v2 saves as classic (variant missing
      → `"classic"`), v3 requires a registered variant name and
      `variant_data` passing `restore_data`
- [ ] `stats.lua`: log entries gain optional `variant` (default `"classic"`,
      backfilled on load) + `variant_data`; `summary()` gains per-variant ×
      per-difficulty sections (count/avg/best/mistakes) beside global totals
      (data-only in M13; `statsview` rendering is M15)
- [ ] `main.lua` + `ui/dialogs.lua`: variant picker dialog
      (`ui/variants.lua` — ordered localized id/label list, spec) inserted
      before the difficulty picker; only Classic selectable until M14/M15
- [ ] Parity + performance guard: `sudoku_solver_spec`, `sudoku_hints_spec`,
      `sudoku_game_spec` stay green unchanged; `sudoku_game_serialize_spec`
      gains v2-accept + v3-round-trip cases (the VERSION assertion moves to 3);
      `tools/bench_propagation.lua`, `tools/bench_solver.lua`,
      `tools/bench_generation.lua` gates unchanged (classic hot paths must not
      regress)

**Exit criteria**: all specs green via `./dev.sh test`, `./dev.sh lint`
clean, `./dev.sh fmt` clean, bench tools pass their gates, emulator boot
smoke on `kobo-aura-one` with no errors (touches game/save code), PLAN.md +
README updated, commit.

### M14 — Sudoku X (variant: diag)

Planned (decisions resolved with the user): **X-specific techniques are in
scope from day one** — the two diagonals become registered units, so
diagonal naked/hidden subsets and diagonal locked candidates come nearly
free from the M13 unit plumbing; the shared fish engine (already generic
over base/cover units per M2c) is generalized to accept diagonal units;
AIC `sees` topology stays classic (candidate filtering carries the diagonal
constraint; chains remain sound). Difficulty shares the same 6 tiers with
X-specific calibration (measured in this milestone, P3-style). Generator
reuses the whole classic pipeline (sample → dig → classify) with the
diag-aware solver, so uniqueness and classification automatically respect
the diagonals.

- [ ] `core/variants/diag.lua`: two diagonal units (index 0: NW–SE, index 1:
      NE–SW); `extra_units`, `extra_peers` (the 8 other diagonal cells, for
      subtractive candidate updates), `is_safe_extra` (diagonal presence),
      `each_conflict_peer`, `validate_board` (each diagonal holds 1–9 —
      implied by no-dups on a full board, but validated explicitly for
      puzzle/solution data)
- [ ] `core/techniques/units.lua`: `units.diag_cells(idx)`,
      `units.diag_unit(idx)`, diagonal units in `for_each_unit(fn, variant)`;
      spec
- [ ] Unit-scanning techniques: switch their unit iteration to
      `prop:for_each_unit` (M13 plumbing; the diag descriptor activates
      diagonal scanning). Port X example puzzles (diagonal locked
      candidates, diagonal hidden pair, diagonal naked subset) as failing
      specs per technique; pattern metadata records the diagonal unit
      descriptor (`type = "diag"`), already generic
- [ ] `core/techniques/fish.lua`: generalize base/cover unit selection to
      unit descriptors so a diagonal can serve as base or cover (sizes 1–2;
      larger diagonal fish only if ported examples demand them); spec with a
      diagonal-X-Wing example. Diagonal fish are geometrically degenerate,
      not pure plumbing: each diagonal crosses every row/col exactly once,
      and the two diagonals share the center cell (a center cell sits on
      both base lines) — the generalization must verify crossing/intersection
      semantics explicitly, with any ambiguity resolved in the spec example
- [ ] `core/generator.lua`: `generate`/`generate_game` accept
      `variant = "diag"`; the **sampler must be variant-aware** — a classic
      `sample_solution` grid satisfies both diagonals only ~1 in 10⁶ times
      ((9!/9⁹)² per grid), so sampling classic + resample-on-reject never
      terminates; X sampling fills an empty grid through the diag-aware
      solver (M13 plumbing), then digs/classifies as planned; per-variant
      difficulty calibration tables (keep the
      classic tables as defaults; add a variant-keyed override layer);
      measure hit rates and record the calibrated X ranges/weights in
      PLAN.md (P3/RM4 methodology); `solve_path.classify` beginner/easy
      clue-count split reused for X
- [ ] `game.lua` + `game_serialize.lua`: variant `"diag"` end-to-end —
      diagonal duplicate marking, autofill/fill-all-notes respect the
      diagonals, save round-trip; specs
- [ ] `ui/sudokuview.lua`: paint the two diagonals (thin gray band below the
      digit ink, distinct from grid lines); `sudoku_view_spec` pixel checks
- [ ] `main.lua`/`ui/dialogs.lua`: "Sudoku X" enabled in the variant picker;
      l10n labels + pot extraction
- [ ] `tools/bench_generation.lua`: X generation gate (≤ 3 s per sample)

**Exit criteria**: all specs green, `./dev.sh lint`/`./dev.sh fmt` clean,
X calibration numbers recorded in PLAN.md, emulator boot smoke on
`kobo-aura-one` (play one X game), PLAN.md + README updated, commit.

### M15 — Killer: playable with predefined puzzles

Planned (decisions resolved with the user): the first Killer milestone
delivers the **core cage model, solver support, validation, and UI**, using
**6 predefined puzzles** (one per difficulty tier) stored as a pure data
module. Killer puzzles have **no givens**: the board starts empty, the
puzzle data is the cage set, and difficulty labels are stored (not
classified). **The hint pipeline runs unmodified and stays sound**: cage
pruning keeps all 17 techniques sound, so the M4 pipeline executes — but
with zero givens and no cage-combination technique until M16, hints on a
fresh Killer board are sparse (mostly "no hint" until the board fills); the
first genuinely useful Killer deduction (cage combinations) arrives in M16.
The second Killer milestone (M16) adds algorithmic generation, Killer
techniques, and difficulty calibration.

**Cage model** (specified for the implementer):
- A cage = `{ sum = N, cells = { {r,c}, ... } }`; cages partition all 81
  cells exactly (no overlap, no gap), each holds 1–9 cells, `sum` is an
  integer in 1..45, digits within a cage are distinct, and the placed digits
  sum to `sum`. All of this is validated by `restore_data` and enforced by
  the solver.
- **Live mistake rule** (game conflict marking): for a cage, let S = sum of
  placed digits and E = count of empty cage cells. A cage is in violation
  iff `S + E > sum` (unreachable) or (`E == 0` and `S ~= sum`). All *filled*
  cells of a violating cage are marked conflicting.
- **Candidate pruning**: per cage, the set of valid digit combinations
  (distinct digits summing to `sum`, consistent with already placed digits);
  a cell's candidates = classic legal mask ∩ (union of digits over the
  cage's valid combos). Combination tables for (size, target) are
  precomputed module-level once. Empty candidate set = contradiction (the
  backtracker dead-ends naturally).
- **Note auto-clean**: placing a digit removes it from the notes of
  `each_conflict_peer` cells (cage-mates), consistent with classic peers.

- [ ] `core/variants/killer.lua`: `restore_data` (strict cage-table
      validation incl. partition check), `new_state` (per-cage combo state,
      derived from board+masks; rebuild-per-node is the accepted first
      pass), `filter_candidates`, `after_place`/`after_remove` (restrict/
      expand the cage's combos), `refresh_candidates` (recompute all cells
      of the affected cage), `is_safe_extra` (no cage duplicate),
      `each_conflict_peer` (cage-mates), `validate_board` (every cage sums
      exactly), `serialize_data`
- [ ] `core/variants/killer_puzzles.lua`: 6 puzzles (one per tier), each
      `{ id, difficulty, cages = {...}, solution = "81-char" }`. Verify in
      specs: cage partition valid, solution satisfies every cage + global
      rules, `count_solutions(2) == 1` per puzzle, and the puzzle solves
      guess-free with the technique set available in M15 (classic 17 +
      pruning; if any tier puzzle needs more, pick a replacement or downgrade
      its tier — record the decision in PLAN.md)
- [ ] Solver/candidates specs (`sudoku_variant_killer_spec.lua`): combo
      pruning (e.g. 2-cell cage sum 3 ⇒ both cells {1,2}; sum 17 ⇒ {8,9};
      single-cell cages force the digit), dead-end rollback, all 6 puzzles
      solve to their stored solution
- [ ] `game.lua`: zero-given allowance for Killer; cage violations in
      `conflicts_board`; cage-aware auto-clean; specs (marking, undo/redo,
      notes)
- [ ] `game_serialize.lua`: `variant_data` cage round-trip; v3 restore
      validates cages; specs
- [ ] `stats.lua`: entries carry `variant = "killer"` + `variant_data`
      (cages) so history replay is lossless; games-list rows show the
      variant; `ui/statsview.lua` renders the M13 per-variant `summary()`
      sections
- [ ] `main.lua`/`ui/dialogs.lua`: variant picker → Killer difficulty picker
      selects the predefined puzzle (deterministic per difficulty);
      replay/"Play again" rebuilds the game from the stored cages+solution
      (no generator involvement)
- [ ] `ui/sudokuview.lua` variant extras (Killer): cage borders (a dark line
      on every cell edge whose two cells are in different cages, over the
      grid lines), sum label (small corner digit, top-left cell of each
      cage; `layout.lua` gains a `FONT_SUM_DP` constant), per-cage
      completion highlight (light fill when a cage is filled and correct —
      theme color); `sudoku_view_spec` pixel checks
- [ ] l10n: variant names ("Killer Sudoku"), cage-data error messages; pot
      extraction + German catalog
- [ ] Emulator smoke: full loop (menu → play a Killer puzzle → notes → hints
      → win → stats shows the variant) on `kobo-aura-one`

**Exit criteria**: all specs green, `./dev.sh lint`/`./dev.sh fmt` clean,
emulator smoke, PLAN.md + README updated, commit.

### M16 — Killer generation, techniques & difficulty

Planned (decisions resolved with the user): **algorithmic Killer
generation** (not a puzzle bank) plus the **Killer technique family** that
makes Killer hints and difficulty meaningful. This is the highest-risk
milestone; expect P3/RM4-style iterative calibration, and treat the
generator pipeline and the calibration as separate tasks.

**Killer techniques** (new technique modules with the existing
`apply(prop)`/`flags()` interface; registered **per-variant** per design
decision #11 — the propagator runs them only in Killer solves, and the
classic composites stay untouched):
- `killer_combinations` — cage combo restriction/placement (the most basic
  Killer deduction; order right after `hidden_singles`). Flag bit 2 (free
  region), tier easy in the per-variant technique table.
- `killer_45_rule` — innies/outies: house sum 45 vs the cages intersecting
  a row/col/box yields hidden cage sum constraints. Flag bit 13 (free
  region), tier medium in the per-variant technique table.
- Patterns: `kind = "cage_combination"` / `"innie_outie"` with cage cells +
  values; `flags.TECHNIQUE_SCORES` entries (combinations 15, 45-rule 40);
  l10n labels; specs with ported example puzzles (choose small, well-known
  Killer examples and record sources in the spec headers).

**Generator** (`core/generator.lua` + killer helpers):
1. Sample a full classic solution grid (existing `sample_solution`).
2. Tessellate: partition the 81 cells into cages of 1–9 cells (start from
   singletons, randomly merge adjacent cages; adjacency preferred for
   visual quality, size ≤ 9 enforced). Each cage's target = the sum of its
   digits in the sampled solution (guarantees a solution exists).
3. Difficulty shaping: uniform tessellation yields easy puzzles; harder
   tiers need crafted structure — define measurable cage-structure metrics
   (share of 2-cell cages, cage alignment with boxes, count of cages
   crossing box borders, average cage size) and use weighted sampling +
   measurement to hit each tier (P3 methodology; iterate until measured hit
   rates are usable, record the calibrated tables in PLAN.md).
4. Uniqueness + classification: mirror classic `classify_puzzle` — killer
   `TIER_TECHNIQUES` per difficulty from the per-variant technique tables
   (classic ∪ killer), `count_solutions(2)` with killer techniques, P4
   search budget, no guessing. `solve_path.classify`'s clue-based
   beginner/easy split must become variant-aware (Killer: e.g.
   combinations-only solve vs. 45-rule).
5. Payload: `{ board = empty, solution, cages, difficulty, variant, seed }`.

- [ ] `core/techniques/flags.lua`: allocate the killer flag bits (2, 13) in
      the shared registry only — the classic tier composites
      (`EASY = 0xFF`, `MEDIUM`, `ALL`) stay byte-identical, so killer
      techniques never execute in a classic solve; killer tiers (easy /
      medium) live in the per-variant technique table
- [ ] `core/techniques/killer_combinations.lua` + spec
- [ ] `core/techniques/killer_45_rule.lua` + spec
- [ ] `propagator.lua`: per-variant technique selection — the propagator
      builds its order as `classic ∪ variant:techniques()` (M13 plumbing);
      `hints.lua` TECHNIQUES entries gain the same per-variant composition
- [ ] `core/generator.lua`: killer generation pipeline (steps 1–5 above) +
      per-variant tier technique tables + variant-aware classification
- [ ] Calibration: measurement run (`tools/bench_generation.lua` extended
      with a Killer gate, ≤ 3 s per sample on the dev Mac), hit-rate tables
      recorded in PLAN.md
- [ ] `main.lua`/`ui/dialogs.lua`: Killer difficulty picker switches from
      the predefined set to generated puzzles
- [ ] l10n for the new technique names; pot extraction

**Exit criteria**: all specs green, `./dev.sh lint`/`./dev.sh fmt` clean,
`tools/bench_generation.lua` killer gate passes, emulator boot smoke on
`kobo-aura-one` with no errors, calibration numbers recorded in PLAN.md,
PLAN.md + README updated, commit.

### M17 — Seed-ID & Required Techniques in Stats & Victory Dialog (v1.1.0) (done)

Display the puzzle generation seed and the canonical list of required human solving techniques across game statistics views and solved puzzle menus.

- [x] `core/techniques/flags.lua`: single source of truth for canonical 17 techniques catalog (`flags.TECHNIQUES`, `flags.TECHNIQUE_BY_ID`, `flags.TECHNIQUE_BY_FLAG`).
- [x] `core/solve_path.lua`: extract and canonically order all unique technique IDs used in solve steps (`result.techniques`).
- [x] `core/generator.lua`: forward `techniques = classification.techniques` into game payload with documented tier-restricted equivalence.
- [x] `game.lua`: accept, store, serialize, and report `techniques` in records and getters (preserves `nil` when unset; forward-compatible string validation).
- [x] `game_serialize.lua`: serialize and restore `techniques` list with forward-compatible validation.
- [x] `stats.lua`: validate and persist optional `techniques` on game log entries with forward-compatible validation and `merge_entry` preservation.
- [x] `ui/techniques.lua`: `techniques.format_required(list, max_items)` helper suppressing basic singles (`naked_singles`, `hidden_singles`) when advanced techniques are required, or returning `"Singles only"` (localized in German as `"Nur Einer"`), supporting `max_items` truncation (`"+%1 more"`).
- [x] `ui/techniques.lua`: bounded LRU memoization (`DERIVE_CACHE`) and search budget cap (`search_budget = 200`) in `techniques.derive(puzzle_str)`.
- [x] `stats.lua`: `stats.summary()` aggregates `hints_per_technique` exclusively from completed games (`finished`, `give_up`, `abandoned`), avoiding mid-game spoiler ranking.
- [x] `ui/gamedetail.lua`: display `Seed: <seed>` and `Techniques: <techniques>` with solver fallback and memoization for legacy records; suppress techniques on `in_progress` puzzles.
- [x] `ui/gamedetail.lua`: compact layout with adaptive MiniGrid sizing (`min(w * 0.5, h * 0.36)`) and two-column inline stat pairing.
- [x] `ui/dialogs.lua`: display `Seed: <seed>` and `Techniques: <techniques>` in win dialog with paired compact stats and `max_items = 4` capping.
- [x] `_meta.lua`: bump version to `"1.1.0"`.
- [x] Automated catalog drift integrity specs and comprehensive 17-technique ordering tests.
- [x] `core/util.lua`: `util.format_seed(seed)` formatting seeds into space-separated 4-digit groups (e.g. `4354 5433 6455 32`).
- [x] `ui/gamedetail.lua`: seamless previous/next game navigation via `◀` / `▶` buttons, hardware paging/arrow keys, and swipe gestures; suppress "Correct placements" on finished games.
- [x] `CHANGELOG.md` updated for v1.1.0.

**Exit criteria**: all unit and integration specs green, `./dev.sh lint` clean, `./dev.sh fmt` clean, emulator boot smoke on `kobo-aura-one` and `kobo-clara` (6") with no errors.
