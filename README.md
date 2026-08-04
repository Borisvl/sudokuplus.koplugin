# Sudoku for KOReader

A Sudoku puzzle game for e-ink readers, implemented as a KOReader plugin
(target: Kobo). Requirements and milestone plan live in PLAN.md; project
rules in AGENTS.md.

## Project structure

```
sudoku/
├── sudoku.koplugin/     # plugin source (main.lua, _meta.lua, core/, ui/, …)
├── tests/unit/          # busted specs, symlinked into the koreader checkout
├── third_party/koreader # KOReader checkout (gitignored, dev dependency)
├── third_party/rustoku  # pinned rustoku reference for the core port (gitignored)
├── dev.sh               # build + launch emulator, or run tests (`./dev.sh test`)
├── env.sh               # Homebrew PATH setup (required by KOReader builds)
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

### Linting

```sh
source env.sh
luacheck sudoku.koplugin/
```

Uses the project's `.luacheckrc`, which mirrors KOReader's
(`unused_args = false`, implicit `self`).

### Deployment to a device (later)

Copy the `sudoku.koplugin/` folder onto the Kobo's
`.adds/koreader/plugins/` directory over USB.

## Status

- [x] Dev environment: emulator builds and runs on macOS (Apple Silicon)
- [x] Plugin skeleton registers in the Tools menu
- [x] M0: test harness (specs symlinked, `./dev.sh test`), rustoku pinned
- [ ] M1: core foundations (board, masks, candidates, solver)
- [ ] M2: techniques (easy → expert, per tier, test-first)
- [ ] M3: solve path, difficulty, generation
- [ ] M4: hint engine
- [ ] M5: game state machine + storage
- [ ] M6: game UI (e-ink first)
- [ ] M7: menus, hint display, stats screen
- [ ] M8: polish, i18n, on-device testing

See PLAN.md for milestone details and the project rules in AGENTS.md.
