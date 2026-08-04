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
8. **v1 UI difficulties**: Easy, Medium, Hard; Expert puzzles behind a
   setting (once AIC hints are solid).
9. **Stats storage**: JSON file in KOReader's data dir via `persist.lua`.
   Time stats count finished games; give-ups are recorded separately.
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
├── storage.lua                  # JSON persistence via KOReader persist.lua
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

- [ ] `board.lua` (grid, 81-char parse/serialize, duplicate detection)
- [ ] `masks.lua`, `candidates.lua`
- [ ] `solver.lua`: MRV backtracking `solve_any` / `solve_until` / `solve_all`
- [ ] Inject a pure-Lua PRNG (xoshiro-style) for deterministic shuffle
- [ ] Port rustoku's core test suite (puzzle→solution pairs, multi-solution
      counting, invalid input)

**Exit criteria**: all tests green, luacheck clean.

### M2 — Techniques (port per tier, test-first each)

- [ ] M2a Easy: naked singles, hidden singles
- [ ] M2b Medium: naked/hidden pairs, locked candidates, naked/hidden triples
- [ ] M2c Hard: X-Wing, naked/hidden quads, Swordfish, Jellyfish, Skyscraper
- [ ] M2d Expert: W-Wing, XY-Wing, XYZ-Wing, AIC
- [ ] `solve_path.lua`: steps record technique flags + pattern metadata
- [ ] `propagator.lua`: deterministic iteration loop, rollback on dead ends

**Exit criteria**: every technique matches its HoDoKu example (eliminations
and placements), whole-puzzle solve paths correct; each technique has its
own failing-then-green spec.

### M3 — Solve path, difficulty, generation

- [ ] Difficulty classification: hardest technique used in solve path
- [ ] `generator.lua`: solved-board sampling → clue removal preserving unique
      solution (`solve_until(2)`), symmetry modes, difficulty-targeted retry
      loop
- [ ] Performance sanity in emulator: generation ≤ a few seconds worst case

**Exit criteria**: property tests — unique solutions; Easy never needs more
than easy techniques; Hard needs (e.g.) skyscraper-level; clue-count ranges.

### M4 — Hint engine (core)

- [ ] `hints.lua`: next applicable technique for current board state
- [ ] Progressive levels: ① name → ② pattern cells → ③ apply
- [ ] Missed-strategy classification (hint requested ⇒ technique missed)

**Exit criteria**: hints verified against HoDoKu examples; level semantics
tested; stats feed point defined.

### M5 — Game state machine + storage (UI-free, testable)

- [ ] `game.lua`: notes/pencil marks, given-cell lock, undo/redo history,
      live conflict marking (rule violations only), `check_for_errors()`
      (solution comparison), timer (injected time), win detection,
      save/restore serialization
- [ ] `stats.lua` + `storage.lua`: JSON via persist.lua; per game —
      difficulty, duration, hints requested (→ missed strategies), mistakes,
      check-revealed errors; give-ups recorded separately

**Exit criteria**: state machine + aggregation specs green; save/load
round-trip test.

### M6 — Game UI (e-ink first)

- [ ] `sudokuview.lua`: grid painted with BlitBuffer — thick 3×3 box borders
      vs thin cell lines; givens bold vs user entries; notes as small digits;
      selection + live conflict highlight; "Check board" state showing all
      wrong numbers; night-mode safe; no animations
- [ ] Input: tap to select; number bar (1–9, erase, notes toggle, hint,
      check); undo/redo; pause menu

**Exit criteria**: fully playable in the emulator (smoke check).

### M7 — Menus, hint display, stats screen

- [ ] Tools menu: New Game (difficulty picker), Continue, Statistics
- [ ] Hint overlay with pattern highlighting (progressive reveal)
- [ ] `statsview.lua`: avg/best time per difficulty, hints per technique,
      most missed strategies, streak, games played/given up
- [ ] Expert difficulty behind a setting

**Exit criteria**: complete loop — generate → play → hints → win → stats —
in the emulator.

### M8 — Polish, i18n, deployment

- [ ] gettext-marked strings, settings (e.g., notes on/off)
- [ ] README: deploy instructions, rustoku pin update
- [ ] Kobo on-device smoke test

**Exit criteria**: milestone report, final commit.
