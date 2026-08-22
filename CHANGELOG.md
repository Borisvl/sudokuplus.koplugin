# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-22

### Added
- **Custom Strategy Practice Mode**:
  - Target and practice specific solving strategies on demand across Medium, Hard, Master, and Expert tiers.
  - Multi-select strategy picker to practice individual techniques or custom combinations.
  - Dedicated training modes and clear explanations for **X-Chain** and **XY-Chain** chain logic.
- **Improved Hint Engine & Batch Eliminations**:
  - Step 3 now applies all candidate eliminations deduced by a technique instance at once (e.g. clearing all obsolete notes for a Locked Candidates or Naked/Hidden Subset in a single tap).
  - Look around without losing your place: inspect the board, cycle digits, toggle notes, or change cell selection without dismissing an active hint banner.
  - Applying hint eliminations with notes disabled automatically materializes remaining legal candidates on affected cells.
  - Hint requests are deduplicated per board state so inspecting hints repeatedly does not penalize statistics.
- **Statistics & Game History Enhancements**:
  - Browse seamlessly across games in the history log using previous/next buttons (`◀`/`▶`), hardware page-turn keys, arrow keys, or swipe gestures without closing the view.
  - Formatted puzzle seeds (`Seed: 4354 5433 …`) and required solving techniques displayed in victory dialogs and game details for easy sharing and replaying.
  - Spoiler protection: required techniques and strategy rankings remain hidden for active in-progress games until completed.
  - Dedicated statistics tracking and history breakdown for Custom practice mode alongside standard difficulty tiers.
  - Redesigned game detail view with adaptive mini-grid sizing and clean two-column stat pairing tailored for e-ink screens.

### Changed
- **Exact-Tier Puzzle Generation & Faster Creation**:
  - Standard difficulty requests now strictly match the chosen difficulty without falling back to nearby tiers.
  - Generator hot paths are significantly optimized, creating Master and Expert puzzles more than twice as fast.
  - Clean Retry / Cancel dialog with search budget escalation if an exact match requires more attempts.
- **Enhanced Save Safety & Session Reliability**:
  - Automatic game checkpoints on pause, device sleep, and app exit prevent lost progress.
  - Graceful recovery options (Retry / Discard) if storage writes encounter errors.
  - Complete plugin module isolation to ensure smooth, conflict-free operation alongside KOReader and other plugins.
- **Difficulty Progression Realignment**:
  - Reclassified **Swordfish** into Master tier alongside X-Wing and Skyscraper for a smoother difficulty curve.

## [1.0.0] - 2026-08-15

Initial release of **Sudoku+** (`sudokuplus.koplugin`), a full-featured, logical Sudoku puzzle game and tutor for KOReader.

### Added
- **17 Logical Solving Techniques**: Complete human-technique solver ported from `rustoku` / HoDoKu logic, including Naked/Hidden Singles, Pairs, Triples, Quads, Locked Candidates, X-Wing, Swordfish, Jellyfish, Skyscraper, W-Wing, XY-Wing, XYZ-Wing, and Alternating Inference Chains (AIC).
- **Human-Grade Puzzle Generator**:
  - 6 balanced difficulty tiers: Beginner, Easy, Medium, Hard, Master, and Expert.
  - 5 grid symmetry modes (Rotational 180°, Rotational 90°, Diagonal, Horizontal, Vertical) plus asymmetric generation.
  - Guarantee of unique solutions solvable with pure deduction (zero guessing required).
- **Progressive 3-Stage Hint Engine**:
  - Step 1: Technique Identification & Explanation (e.g. "Skyscraper on candidate 5 in rows 2 and 7").
  - Step 2: Visual Highlight (highlights base cells, pincers, and candidate eliminations on the grid).
  - Step 3: Action Execution (applies the deduction directly to notes or fills the cell).
- **E-Ink Refresh Engine**:
  - Flicker-free partial refresh pipeline with per-cell dirty region bounding.
  - Dedicated `"ui"` hardware refresh modes avoiding unnecessary full-screen flashes during gameplay.
  - High-contrast, clean typography tailored for Kobo, Kindle, PocketBook, and Android e-readers.
- **Rich Analytics & Game History**:
  - Complete player dashboard: games played, win rate, best/average times, current & best streaks, mistake counters, and most-missed technique insights.
  - Interactive game history browser with miniature board visualizations.
  - Seed-based puzzle replay system to retry specific boards or share puzzles.
- **Quality-of-Life Controls**:
  - Pen & Pencil note-taking modes with automatic note pruning upon digit placement.
  - "Auto-fill notes" helper setting.
  - Live rule-violation detection & on-demand "Check Board" solver verification.
  - Full Undo / Redo history stack.
- **Interactive In-Game & Menu Help Section**:
  - Structured, two-topic guide ("How to play & controls", "Features, hints & tools") with rich Markdown formatting (`text_format = "md"`).
  - Accessible directly from both the main KOReader Tools menu and the in-game pause dialog.
  - Explains number-first input, notes mode, long-press gestures, matching digit highlights, hardware key navigation, 3-step hints, conflict detection, auto-clean, difficulty tiers, and statistics.
- **Internationalization (i18n)**:
  - Complete gettext catalog (`sudokuplus.pot`) with English and German (`de`) translations out of the box.
- **Open-Source Tooling**:
  - Comprehensive test suite (47 suites: 39 pure-Lua headless + 8 KOReader integration specs).
  - Automated CI (Luacheck + StyLua + Busted).
  - Release packager script generating clean, install-ready `.zip` archives.
