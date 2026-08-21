# Sudoku+ for KOReader

[![CI](https://github.com/Borisvl/sudokuplus.koplugin/actions/workflows/ci.yml/badge.svg)](https://github.com/Borisvl/sudokuplus.koplugin/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/Borisvl/sudokuplus.koplugin?style=flat&color=3388ee)](https://github.com/Borisvl/sudokuplus.koplugin/releases)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![KOReader](https://img.shields.io/badge/KOReader-Plugin-orange.svg)](https://github.com/koreader/koreader)

A full-featured, logical Sudoku puzzle game and interactive tutor crafted specifically for e-ink readers running [KOReader](https://github.com/koreader/koreader) (Kobo, Kindle, PocketBook, Android).

<p align="center">
  <img src="doc/screenshots/sudoku_plus.png" alt="Sudoku+ Gameplay on KOReader" width="480">
</p>

---

## ✨ Features

- **🧠 17 Human Deductive Technique Families, 19 Selectable IDs**: Complete logical solver ported from `rustoku` and HoDoKu logic, with AIC split into X-Chain, XY-Chain, and General AIC for targeted practice. Every puzzle is 100% uniquely solvable through human deduction without guessing or brute-force trial-and-error:
  - *Basic*: Naked/Hidden Singles, Naked/Hidden Pairs, Triples, and Quads
  - *Intersections*: Locked Candidates (Pointing & Claiming)
  - *Wings & Fish*: X-Wing, Swordfish, Jellyfish, Skyscraper, W-Wing, XY-Wing, XYZ-Wing
- **🎯 6 Balanced Difficulty Tiers**: Beginner, Easy, Medium, Hard, Master, and Expert, backed by an algorithmic generator with 5 symmetry modes (Rotational 180°, Rotational 90°, Diagonal, Horizontal, Vertical) plus asymmetric boards.
  1. **Identify**: Teaches you the next logical technique to look for.
  2. **Highlight**: Highlights the pattern cells, pincers, and affected candidate eliminations directly on your board.
  3. **Apply**: Executes the elimination or digit placement for you.
- **⚡ E-Ink Optimized Display**:
  - Region-bounded per-cell partial refreshes with zero full-screen flashing during normal tap-and-play.
  - High-contrast typography and night-mode safe themes.
- **📊 Rich Analytics & Game History**:
  - Track total games, win rates, per-difficulty completion times, and active streaks.
  - Identify your most-missed solving techniques.
  - Interactive game log with mini-board previews and seed-based puzzle replay.
- **✏️ Pen & Pencil Controls**:
  - Fast single-tap digit entry and dual-mode pencil notes.
  - Optional "Auto-fill notes" and live rule-violation detection.
  - On-demand "Check Board" solver verification with clear strikethrough feedback.
  - Full Undo / Redo history.
- **🌐 Multilingual**: Built-in localization support (English, German included out-of-the-box).

---

## 📥 Installation

1. Download the latest **`sudokuplus.koplugin.zip`** from the [Releases](https://github.com/Borisvl/sudokuplus.koplugin/releases) page.
2. Connect your e-reader to your computer via USB.
3. Extract the archive into the plugins directory of your device:
   - **Kobo**: `.adds/koreader/plugins/sudokuplus.koplugin/`
   - **Kindle / PocketBook / Android**: `koreader/plugins/sudokuplus.koplugin/`
4. Safely eject and disconnect your device.
5. Restart KOReader.
6. Open the top menu &rarr; **Tools** (gear icon) &rarr; **Sudoku+**.

---

## 🎮 How to Play

- **Select Cell**: Tap any empty or filled cell on the 9×9 grid.
- **Enter Digits**: Tap numbers 1–9 on the bottom number bar.
- **Pencil Notes**: Toggle the **Notes** button (pencil icon) to enter candidate notes. Placing a definitive digit automatically prunes notes from intersecting rows, columns, and 3×3 boxes.
- **Check Board**: Tap **Check** to verify your board against the solution. Incorrect entries are struck through in ink and keep a shaded background until corrected.
- **Hints**: Tap **Hint** whenever you are stuck to receive progressive guidance on the next logical technique.
- **Replay Game**: Visit **Statistics** &rarr; select any finished or abandoned game from the log &rarr; tap **Play again** to retry the exact puzzle seed.

---

## 🛠️ Developer Guide

### Project Structure

```
sudokuplus.koplugin/
├── core/                # Pure Lua logical solver & generator (0 KOReader UI deps)
│   ├── board.lua        # 81-cell grid bitmask engine
│   ├── candidates.lua   # Candidate cache management
│   ├── generator.lua    # Deterministic seeded puzzle generation & symmetry
│   ├── hints.lua        # Progressive 3-stage hint derive engine
│   ├── solver.lua       # MRV backtracking & technique classification
│   └── techniques/      # 17 technique families exposed as 19 classified IDs
├── ui/                  # KOReader widget UI, e-ink refresh engine & menus
├── game.lua             # Pure game state machine (undo/redo, notes, timer)
├── stats.lua            # Pure statistics & game history log engine
├── storage.lua          # Storage serialization
└── l10n/                # Gettext translation catalogs (.pot, .po, .mo)
tests/unit/              # Busted specs (47 suites: 39 pure-Lua headless + 8 KOReader UI)
tools/                   # Headless benchmarks and release packaging scripts
dev.sh                   # Build, lint, test, format, and emulator launcher
```

### Development Commands

```sh
# Run the local KOReader emulator with live symlinked plugin
./dev.sh

# Run all 47 plugin specs (39 core, then 8 isolated frontend)
./dev.sh test

# Run one test category
./dev.sh test --core
./dev.sh test --frontend

# Run a specific test
./dev.sh test tests/unit/sudoku_hints_spec.lua

# Run manifest, isolation, package, release, and workflow contract tests
./dev.sh test-tooling

# Check code formatting and static analysis (luacheck + stylua)
./dev.sh lint

# Apply automatic code formatting
./dev.sh fmt

# Extract translatable strings into gettext catalog
./dev.sh pot

# Deploy directly to a USB-connected Kobo
./dev.sh deploy

# Package clean release zip archive
./tools/package_release.sh
# Outputs dist/sudokuplus.koplugin.zip and its .sha256 sidecar

# Publish after dating CHANGELOG.md and committing the release version
git tag v1.1.0
git push origin v1.1.0
```

Stable `vX.Y.Z` tags run every CI and package gate before publishing. If a tag
was placed on the wrong commit, force-moving and pushing it reruns the gates and
updates the existing release and assets.

---

## 📜 License & Credits

- **License**: Released under the **[GNU Affero General Public License v3.0 only (AGPL-3.0-only)](LICENSE)**. Copyright © 2026 Boris von Loesch and contributors.
- **Solver & Techniques**: The Lua core is a port of **[rustoku](https://github.com/huangsam/rustoku)** (MIT License) by Samuel Huang. Pinned reference commit: `afef526d93fa176d75b4c8350cc387b10be6928b`.
- **Techniques & Test Fixtures**: Technique definitions and standard test boards derive from the **[HoDoKu](https://hodoku.sourceforge.net/)** project by Bernhard Hobiger.
- **Notices**: Complete rustoku and HoDoKu attribution and license details are in **[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)**, **[COPYING.GPL-3.0](COPYING.GPL-3.0)**, and **[COPYING.FDL-1.3](COPYING.FDL-1.3)**.
- **Platform**: Built for **[KOReader](https://github.com/koreader/koreader)**.
