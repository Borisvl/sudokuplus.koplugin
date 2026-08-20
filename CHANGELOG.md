# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-08-16

### Added
- **Seed-ID Display**: Show the puzzle generation seed in both the Game Detail view and the victory dialog to facilitate sharing, replaying, and debugging puzzles.
- **Required Solving Techniques**: Display the logical deduction techniques used by the canonical solver pass in Game Details and the victory dialog (with basic singles suppressed when advanced techniques are needed).
- **Previous / Next Navigation in Game Details**: Browse seamlessly across games in the game history view using navigation buttons, hardware paging/arrow keys, or swipe gestures without closing the view.
- **In-Progress Spoiler Prevention**: Suppress required technique disclosure for active in-progress games and exclude them from the "Most missed strategies" statistics until completed.
- **Backward-Compatible Technique Classification**: Analyze legacy saves on demand to classify their required techniques without requiring schema migrations.
- **Custom Difficulty & Targeted Strategy Practice Mode**:
  - Practice specific advanced techniques on demand across Medium, Hard, Master, and Expert strategy tiers.
  - Multi-select strategy picker dialog allows choosing any combination of target strategies.
  - Practice constraint enforcement: hints only propose allowed strategies and lower-tier basics.
  - Interactive continue generation dialog with $+50\%$ budget escalation ($100 \to 150 \to 225 \dots$) for rare higher-order techniques.
- **Disjoint Chain Sub-Classification**:
  - Split Alternating Inference Chains into three pedagogical categories: **X-Chain** (single-digit conjugate chains), **XY-Chain** (bivalue cell chains with weak inter-cell links), and general **AIC** (mixed links).
  - Dedicated hint explanations, visual highlights, and localized naming for X-Chain and XY-Chain.
- **Comprehensive Hint Batch Eliminations**:
  - Step 3 of the 3-stage hint reveal now executes all candidate eliminations deduced by the specific technique instance as an atomic batch (e.g. eliminating all obsolete notes for a Locked Candidates or Naked/Hidden Subset instance at once rather than one note per hint).
  - Pattern instance isolation ensures that deductions from separate pattern instances on the board remain cleanly separated.
  - Seamless notes-off support: applying an elimination hint when notes are disabled materializes the remaining legal candidate notes on the affected cells (while preserving any candidates previously removed manually) so deductions are visibly reflected on the grid and consecutive hints advance cleanly.
  - Full undo/redo integration with atomic move history and backward compatibility for existing game saves.

### Changed
- **Difficulty Model Realignment**:
  - Reclassified **Swordfish** from Hard tier to **Master tier** to balance 3x3 fish complexity alongside X-Wing and Skyscraper.

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
