# Sudoku for KOReader

A Sudoku puzzle game for e-ink readers, implemented as a KOReader plugin
(target: Kobo). Requirements and milestone plan live in PLAN.md; project
rules in AGENTS.md.

Statistics: a dashboard (totals, completion/win rates, per-difficulty
times, streaks, mistakes and most-missed techniques) plus a browsable game
history — every started game with its final board and per-game stats, and
"Play again" to re-open an exact puzzle from its reproduction seed.

## Project structure

```
sudoku/
├── sudoku.koplugin/     # plugin source (main.lua, _meta.lua, core/, ui/, …)
├── tests/unit/          # busted specs, symlinked into the koreader checkout
├── third_party/koreader # KOReader checkout (gitignored, dev dependency)
├── third_party/rustoku  # pinned rustoku reference for the core port (gitignored)
├── dev.sh               # build + launch emulator, or run tests (`./dev.sh test`)
├── env.sh               # Homebrew PATH setup (required by KOReader builds)
├── tools/               # headless benchmarks and development utilities
├── AGENTS.md            # project rules (test-first, milestone planning)
├── PLAN.md              # milestone plan and design decisions
└── .luacheckrc          # lint config (mirrors KOReader's own)
```

The plugin is symlinked into KOReader's `plugins/` directory, so edits made
in `sudoku.koplugin/` are picked up by the emulator without copying files.
The same approach is used for specs: `tests/unit/*_spec.lua` is symlinked
into the checkout's `spec/unit/` by `dev.sh`, keeping tests versioned in
this repo while the checkout itself stays gitignored.

## References

The Lua core is a port of [rustoku](https://github.com/huangsam/rustoku)
(MIT). Pinned reference commit:
`afef526d93fa176d75b4c8350cc387b10be6928b` (cloned into
`third_party/rustoku`). Keep this pin up to date as the port progresses and
preserve attribution. Divergences from rustoku (e.g., pattern metadata on
solve steps for the hint system) are documented in PLAN.md.

## Developer guide

### Prerequisites (macOS)

- Xcode Command Line Tools: `xcode-select --install`
- [Homebrew](https://brew.sh/)
- Required packages:

```sh
brew install autoconf automake bash binutils cmake coreutils findutils \
    gnu-getopt libtool make meson nasm ninja pkgconf sdl3 util-linux \
    ccache luacheck
```

KOReader's build requires GNU versions of some macOS tools. `env.sh` prepends
them to `PATH`:

```sh
source env.sh
```

### First-time setup

```sh
git clone https://github.com/koreader/koreader.git third_party/koreader
cd third_party/koreader
source ../../env.sh
./kodev fetch-thirdparty   # pulls base, l10n, fonts, test-data submodules
./kodev build              # first build takes 10-30 min
```

### Running the emulator

```sh
./dev.sh
```

`dev.sh` runs an incremental build (no-op when nothing changed), then
launches the KOReader emulator sized like a Kobo Aura One (1404x1872 @ 300
DPI). Use the SDL window's mouse for touch input.

To iterate: edit files under `sudoku.koplugin/`, quit the emulator
(Alt+F4 / menu), and run `./dev.sh` again. Plugin code loads at startup, so
each change requires a restart.

Other emulator sizes: `./kodev run -s=kindle3`, `-s=hidpi`, or
`-w=W -h=H -d=DPI` (run from `third_party/koreader/` after `source ../../env.sh`).

### Unit tests

Tests run headless via KOReader's busted harness. Specs live in
`tests/unit/*_spec.lua` in this repo and are symlinked into the checkout's
`spec/unit/` directory by `dev.sh` (the `spec/front/unit` path only exists
inside the built emulator output).

```sh
# link specs into the checkout and run one (or all) tests
./dev.sh test koreader-testrunner:sudoku_smoke
./dev.sh test

# manually, from third_party/koreader (after `source ../../env.sh`):
# default (meson) runner — note the test-name format
./kodev test front koreader-testrunner:util
```

The meson runner needs its setup the first time and can appear to hang
then; subsequent runs are fast (< 1 s per test file). Pattern matching
uses meson's `suite:test` names, so plain filenames (`util_spec.lua`) do
not work with the default runner.

### Propagation benchmark

`tools/bench_propagation.lua` measures solver setup and constraint propagation
with KOReader's bundled LuaJIT. It runs the existing technique fixtures plus
deterministic, valid partial boards with 17, 25, 35, and 45 clues. The output
includes p50/p95/maximum timings, AIC cap counts, and a per-technique profile.

From the project root, a quick smoke run is:

```sh
third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit \
    tools/bench_propagation.lua --quick
```

For a larger sample:

```sh
third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit \
    tools/bench_propagation.lua --iterations=5 --generated=20
```

On a device, run the same script with KOReader's bundled `luajit`. The script
derives the project root from its own path, so it does not depend on the
current working directory. Generated boards are propagation stress cases; the
propagation benchmark does not include the M3 puzzle-generation retry loop.

### Generation benchmark

`tools/bench_generation.lua` measures seeded puzzle generation across the six
symmetry modes and the Beginner through Expert difficulty retry loops. It reports
p50/p95/maximum generation time and clue-count ranges, and fails if any sample
exceeds the three-second local sanity limit.

```sh
third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit \
    tools/bench_generation.lua --quick
```

For a larger sample:

```sh
third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit \
    tools/bench_generation.lua
```

The benchmark uses `os.clock()` only in development tooling. Repeat it with
KOReader's bundled `luajit` on the target reader for meaningful device timing.

### Linting and formatting

```sh
source env.sh
./dev.sh lint   # luacheck + stylua --check (style violations fail)
./dev.sh fmt    # apply stylua formatting
```

Linting uses the project's `.luacheckrc` (mirrors KOReader's: `std =
"luajit"`, `unused_args = false`, implicit `self`; specs get `+busted`).
Formatting uses [stylua](https://github.com/JohnnyMorganz/StyLua)
(`brew install stylua`) with `.stylua.toml` (4-space indent, 120 columns,
Unix endings). Note: stylua renders `WidgetContainer:extend {` with a space
before `{`, slightly diverging from KOReader's `extend{` idiom — accepted
for project-wide consistency.

### Deployment to a device

`./dev.sh deploy` syncs `sudoku.koplugin/` to a USB-connected Kobo running
KOReader (plugins land in `.adds/koreader/plugins/` on the device's internal
storage):

- auto-detects the mounted Kobo volume (any volume containing
  `.adds/koreader/plugins/`); override with `KOBO_VOLUME` or `--volume <path>`
- compile-checks every Lua file with the checkout's luajit first, so a
  syntax error never lands on the device
- rsyncs with checksums (`-c`) and `--delete`, so renames and removals are
  mirrored too (checksums matter here because Kobo's FAT driver reports
  unreliable mtimes)
- ejects the volume after syncing (`--no-eject` to skip), then unplug and
  restart KOReader — plugins are only loaded at startup
- `--dry-run` shows what would be copied without changing anything

## Status

- [x] Dev environment: emulator builds and runs on macOS (Apple Silicon)
- [x] Plugin skeleton registers in the Tools menu
- [x] M0: test harness (specs symlinked, `./dev.sh test`), rustoku pinned
- [x] M1: core foundations (board, masks, candidates, MRV solver, PRNG,
      solve path, facade) — fully tested
- [x] M2: techniques (easy → expert, per tier, test-first)
- [~] M3: solve path, difficulty, generation (implementation complete; full
      repository test gate is blocked by the KOReader version target)
- [~] M4: hint engine (core; implementation complete, full repository test gate blocked by KOReader version target)
- [x] M5: game state machine + storage (game.lua, stats.lua, json.lua,
      storage.lua; UI-free, fully tested)
- [x] M6: game UI (e-ink first — sudokuview, numberbar, layout, theme;
      playable loop in the emulator; hint button and menus land in M7)
- [x] M6.1: e-ink refresh optimization (flash-free region-limited
      `"partial"` refreshes; full flashes only on first paint, wake, resize
      and leaving the game)
- [x] M6.2: refresh region refinement (per-cell regions instead of bounding
      boxes; precise check/undo/redo — no more rectangle flashes on device)
- [x] M6.3: one refresh per tap (`"ui"` mode, no promotion flashes, clustered
      regions, tool row only on state change — no more lag/flicker)
- [x] M7: menus, hint display, stats screen
- [x] M9: generation performance (raw board accessors, box-index lookups,
      count-based uniqueness, tiered classification, weighted clue-target
      sampling, search-work budget — ~2.5x on medium/hard, bounded worst case)
- [x] M10: stats dashboard + game history (v2 game log with in-progress
      tracking, v1 migration, insight dashboard, browsable per-game pages
      with miniature board, replay from seed)
- [x] M8a: complete localization & i18n (gettext wrappers across UI, dynamic
      difficulty & status labels, all 17 technique names localized, message
      mapping, `N_` pluralization, `l10n/sudoku.pot` extraction tooling)
- [ ] M8b: polish, deployment, on-device testing

See PLAN.md for milestone details and the project rules in AGENTS.md.
