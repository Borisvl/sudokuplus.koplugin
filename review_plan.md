# Review findings & remediation plan

Extensive review of the whole plugin (core/, techniques/, game.lua, stats,
json, storage, ui/) plus tooling, on 2026-08-09. Lint state at review time:
luacheck 0 warnings / 0 errors. Findings are tracked here so they stop
wandering between sessions (see `review.old.md`); remediation is organized
into milestones below, test-first per AGENTS.md.

Status legend:

- `[ ]` not started
- `[~]` in progress
- `[x]` done

---

## Findings

### Bugs & correctness

1. **Hidden pair detector is stricter than the standard — misses valid pairs.**
   `core/techniques/hidden_pairs.lua:27-34` requires each digit to occur
   *exactly twice in identical cells*. Standard semantics only need the union
   of positions to be ≤ 2 cells (one digit may occur once). Sound but
   incomplete; affects difficulty classification and hints. (Already flagged in
   `review.old.md`.)

2. **Naked triple/quad detectors exclude singleton cells.**
   `naked_triples.lua:16` (`count == 2 or count == 3`) and
   `naked_quads.lua:25` (`count >= 2 and count <= 4`) reject 1-candidate
   cells, so valid subsets containing a singleton are missed. (From
   `review.old.md`.)

3. **`solve_until` returns *zero solutions* when the technique pass
   dead-ends.** `core/solver.lua:283-288`: `if not
   prop:propagate_constraints(...) then return solutions end` returns the
   empty list. Only correct while every technique is sound; silently merges
   "unsolvable" with "technique bug". Should distinguish "0 solutions" from
   "propagation failed".

4. **`propagator.rollback` has a candidate-corrupting fallback path.**
   `core/techniques/propagator.lua:305-316`: a step without a
   `candidate_step_markers` entry falls back to `cand_update` (full
   recompute), discarding earlier eliminations in the pass. Currently
   unreachable (every step sets a marker) but the invariant is silent; should
   assert/error on an unmapped step.

5. **Win-dialog widget-stack leak (verify in emulator).**
   `ui/sudokuview.lua:663-681`: the "New game" / "Statistics" callbacks close
   the view but not the `MultiConfirmBox` dialog, then show the next widget on
   top of the still-open modal; the old dialog can reappear after quitting the
   new game or closing stats.

6. **`restore` trusts a running timer's wall-clock `started` with no sanity
   bound.** `game.lua:1252-1301`. `now()` is wall-clock (`os.time`), so an
   edited save skews `elapsed()` badly. Out of character for an otherwise
   strictly validated restore path.

7. **`main.lua:59` seeds the PRNG with `os.time() + UIManager:getTime()`.**
   `getTime()` is fts-encoded (~1e6-scaled). Harmless as a seed but confusing;
   should be plain `os.time()` or documented.

### Code smells & duplication

8. **`game.lua` reimplements core logic instead of reusing it.**
   `is_safe_board` / `legal_mask_for` (`game.lua:69-99`) and `each_peer`
   (`game.lua:127-146`) duplicate `core/masks.lua` and
   `core/techniques/units.lua` (`peers_of`). Two sources of truth for "legal
   candidate".

9. **Dead code:** `SudokuView:closeMenu` (`ui/sudokuview.lua:794-798`) only
   exercised by specs; pause menu uses `resumeFromPause`. Remove or wire up.

10. **Monolithic files.** `game.lua` (1305 lines: state machine + undo/redo +
    validation + serialization) and `sudokuview.lua` (838 lines: input, paint,
    refresh tracking, hints, dialogs). Core/UI split is clean; intra-file
    concerns aren't.

11. **Unvalidated low-level mutators.** `board.set` (`board.lua:63`) accepts
    out-of-range values; `candidates.set` (`candidates.lua:54`) accepts
    out-of-range masks; `masks.remove_number` (`masks.lua:31`) is a set, not a
    count (safe only because higher layers validate). Documented invariant, but
    low-level API trusts callers.

### Performance

12. **Synchronous puzzle generation on the UI thread.**
    `main.lua:56-61`: `generator.generate_game` runs the retry loop inline,
    blocking input for seconds on Expert. "Generating…" + `forceRePaint`
    communicates but doesn't fix the stall. Biggest on-device UX issue.

13. **AIC/W-Wing hot paths are capped but not device-measured.**
    `aic.lua` (`MAX_EXPANSIONS`, depth 14), `w_wing.lua` (pair enumeration ×
    27-unit bridge scans). The benchmark exists but nothing measures on-device
    p95 for the *hint* path (full propagation per request).

14. **`find_next_empty_cell` is an O(81) full scan per backtracking node.**
    `core/solver.lua:195-213`. Constant factor in generation time.

15. **`game:hint()` rebuilds derived notes with `legal_mask_for` per cell every
    request.** `game.lua:907-917`. Small absolute cost; could be a `masks` call.

### Architecture

16. **`game.lua` is pure yet lives outside `core/` and duplicates core
    helpers.** Zero KOReader deps, so either move it under `core/` or reuse
    core helpers explicitly (see #8).

17. **Difficulty classification depends on technique soundness *and*
    completeness.** `solve_path.classify` treats any flagless placement as
    guessing. Findings #1/#2 make some human-solvable puzzles classify as
    guessing → generation retries → slower and possible difficulty drift.

18. **No save-on-suspend.** Persistence only on explicit quit (`onQuit`);
    suspend/power loss loses all progress. Routine on e-ink readers.

### Missing obvious features

19. **No difficulty shown in-game.** Pause menu shows time/mistakes/hints but
    not difficulty; only the win dialog reveals it.

20. **No pause-menu "New game"** — only Resume/Statistics/Give up/Quit.

21. **No timer/settings exposure** (fixed HH:MM:SS format; no per-difficulty
    goals). Arguably fine for v1.

22. **No re-enter-on-completion.** After a win only New game / Statistics /
    Close; no review-the-solution or same-puzzle replay.

23. **Stats screen truncates without scrolling** (documented "no scrolling in
    v1"); will overflow on the 6" profile with a long technique list.

### Test & tooling gaps

24. **No negative/no-op tests per technique.**
25. **Incomplete-detector cases (#1, #2) untested.**
26. **No independent-solver property test for `generate_game` output**
    (difficulty claim + uniqueness re-solved by the plain solver).
27. **`closeMenu` / win-dialog widget-stack behavior (#5, #9) untested.**
28. **`review.old.md` is committed but not integrated**; open findings should
    live in PLAN.md or here instead of a stray file.

---

## Remediation milestones

### RM1 — Correctness hardening (highest priority) ✅

- [x] #3 `solver.solve_until` / `count_solutions`: a propagation dead-end is
      rolled back and falls through to plain backtracking instead of returning
      a false empty result — a technique dead-end can never hide real solutions
      (technique-less parity holds by construction). New spec: patched unsound
      technique forces a dead-end on a solvable board and the real solution
      count is still found; the `INCONSISTENT` board still reports 0.
- [x] #4 `propagator.rollback`: the silent full-recompute fallback is removed;
      a step without a candidate marker now `error()`s. New specs: foreign
      step → error, checkpoint past the pushed steps → no-op.
- [x] #5 win dialog: the `MultiConfirmBox` is now closed (reference kept) before
      showing New game / Statistics / Close. View spec asserts the dialog is
      closed first on both choices.
- [x] #6 `restore`: a running timer's `started` must be within
      `MAX_TIMER_STARTED_DRIFT` (7 days) of the wall clock, else the save is
      rejected. Serialize-spec covers out-of-window past/future and the
      in-window positive case.
- [x] #7 `main.lua`: PRNG seed is wall-clock epoch **milliseconds**
      (`time.to_ms(time.realtime())`) — `os.time()` alone would collide within
      a second, and the old `os.time() + UIManager:getTime()` mix conflated
      wall-clock with an fts-encoded monotonic value. Menu spec pins the seed
      derivation.

**Exit criteria**: all `sudoku_*` specs green (120 suites OK; the 3 remaining
failures are the pre-existing KOReader `autosuspend`/`batterystat`/`version`
suites), `./dev.sh lint` clean (luacheck 0/0, stylua clean), emulator smoke
covered headlessly by `sudoku_view_spec` (interactive emulator boot not run in
this pass), commit `RM1`.

Committed as `RM1` (see git log).

### RM2 — Solver completeness (classification + hints) ✅

- [x] #1 hidden pairs: standard semantics — a pair is any two digits that both
      occur at least once and whose positions' union is exactly two cells
      (drop the identical-cells / both-exactly-twice requirement; one digit may
      occur once, the other twice). Soundness guard: both digits must be
      present — a union of two cells caused by one digit alone (the other
      absent) is not a pair and would strip legitimate candidates. Specs cover
      the once+twice case (step metadata + cascade-to-assignment), scattered
      digits, a no-confined-union state, and the absent-digit regression.
- [x] #2 naked triples/quads: 1-candidate cells are now eligible (union still
      must be exactly 3/4 digits). Regression specs: triple/quad with a
      singleton is found; degenerate subsets (3 cells/2 digits, 4 cells/3
      digits) are not eliminated from.
- [x] #17 re-verify classification: all `sudoku_*` specs unchanged and green
      (parity, guess-free examples, hints, solve-path). Quantified the impact
      on the #29 medium match rate: the classification distribution over 12
      medium generations (554 retry attempts) is **unchanged** — 498 "easy",
      11 "medium", 12 "hard", 23 "expert", 10 "requires guessing". The old
      detector's strictness only missed rare edge patterns, so RM2 does not
      materially raise the medium match rate; #29 remains a generator-strategy
      problem (see RM4).

**Exit criteria**: technique specs + parity spec green, all six M2c / six M2d
examples still solve guess-free, `./dev.sh lint` clean, commit `RM2`.

### RM3 — Hygiene & deduplication

- [ ] #8 `game.lua`: reuse `core.masks` (`compute_candidates_mask_for_cell`)
      and `core.techniques.units` (`peers_of`-style iteration) instead of
      `is_safe_board` / `legal_mask_for` / `each_peer`; keep `game.lua` pure
      and headless-testable (game specs stay green, no behavior change).
- [ ] #9 remove dead `closeMenu` (or wire it to the pause menu) and delete the
      now-unused specs.
- [ ] #11 add preconditions/docs to `board.set`, `candidates.set`,
      `masks.remove_number` (or move validation into `solver.validate` — the
      real gate).
- [ ] #10 note the monoliths; extract only if it pays for itself (e.g. move
      serialization validation out of `game.lua`).
- [ ] #28 fold `review.old.md` into this file / PLAN.md and remove the stray
      file.

**Exit criteria**: specs green, lint clean, `review.old.md` removed, commit.

### RM4 — Generation responsiveness (architecture, on-device win)

- [ ] #12 move puzzle generation off the UI thread (KOReader `Device:runInSubProcess`
      or a worker with a callback) OR pre-generate/cache puzzles by difficulty
      while idle. Keep `core/` deterministic; the threading lives in the plugin
      layer. Menu/view specs assert the "Generating…" path still works; emulator
      smoke on `kobo-aura-one` and `kobo-clara`.
- [ ] #13 extend `tools/bench_propagation.lua` (or add `bench_hints.lua`) to
      measure the hint propagation path p95; record a device-time budget.
- [ ] #14 if generation still slow, add a dirty-cell/min-heap to
      `find_next_empty_cell` and re-benchmark.
- [ ] #29 **Medium generation is slow and can hard-fail** (measured 2026-08-09,
      profiled before/after RM1 — not a regression). Random 28–34 clue boards
      classify ~90% "easy" under the hardest-technique model, so `generate_game`
      retries ~50× per medium game (≈1–2 s, sometimes the full 100-attempt cap,
      after which medium **fails outright** — observed 1/12 seeds and 1/8 bench
      runs). Per-attempt cost is ~30–80 ms (sample + ~80 uniqueness DFS checks +
      techniques classify). Fixes:
      - generator: bias the medium clue range / accept a difficulty window, and
        make the retry loop resilient instead of hard-failing after the cap
        (return the closest-match puzzle or a clear error);
      - RM2 #1/#2 should raise the medium match rate by reclassifying some
        currently-"easy" boards as medium;
      - re-measure with `tools/bench_generation.lua` and record p50/p95/max.

**Exit criteria**: generation no longer blocks input (or cached puzzles serve
instantly), bench numbers recorded in PLAN.md, specs green, lint clean, commit.

### RM5 — Missing features & test gaps (batch)

- [ ] #19 difficulty label in the game view (and/or pause menu title).
- [ ] #20 "New game" entry in the pause menu (same difficulty, or difficulty
      submenu), wired through `new_game_cb`.
- [ ] #22 review-the-solution / same-puzzle replay option in the win dialog.
- [ ] #18 auto-save on `onSuspend` (writes the same `serialize` the quit path
      does) with a view-spec.
- [ ] #24 negative/no-op specs for every technique.
- [ ] #25 specs for the RM2 edge cases (hidden pair once/twice, naked subsets
      with singletons).
- [ ] #26 property test: generated game → plain-solver uniqueness + solution
      match; difficulty claim checked against an independent classification.
- [ ] #23 stats screen: clamp/scroll the technique list on small screens.
- [ ] #21 optional: per-difficulty stats (already aggregated) surfaced in the
      pause menu.

**Exit criteria**: all new specs green, lint clean, emulator smoke on
`kobo-aura-one` and `kobo-clara`, PLAN.md/README updated, commit.

---

## Priority rationale

Correctness (RM1) first: silent wrong-solution/0-solution results and the
rollback invariant are the only places the solver can misbehave without a
crash. RM2 raises solver completeness, which directly improves difficulty
classification and the hint system the whole game is built around. RM3 is
cheap hygiene that prevents drift. RM4 is the largest user-visible win
(seconds of frozen input on Expert). RM5 bundles the remaining feature and
test gaps that were already agreed in PLAN.md milestones but never landed.
