# AGENTS.md

Project rules for working on the Sudoku for KOReader plugin. These apply to
every session and every agent working in this repository.

## Planning

- Work is organized in milestones, tracked in [PLAN.md](PLAN.md).
- Before implementing a milestone, plan it: break it into tasks, and list the
  open questions it raises.
- Resolve open questions with the user *before* writing code.
- A milestone is done only when all of its exit criteria pass.

## Test-first

- Always write tests before implementation, per milestone and per unit of
  work (e.g., per technique port).
- Start with failing tests, then implement, then make the tests green.
- Do not declare work done without green tests.

## Core library discipline

- `sudoku.koplugin/core/` is pure Lua with **zero KOReader dependencies**
  (no `ui/`, no `UIManager`, no `Device`). It must be fully unit-testable
  headless.
- Keep it deterministic: inject randomness (PRNG) and time instead of using
  `os.time()` / `math.random` directly.
- KOReader-dependent code lives outside `core/` (UI, storage, stats I/O).

## Milestone exit criteria

Every milestone must end with all of:

1. Tests green (`./dev.sh test`),
2. `./dev.sh lint` clean (luacheck + stylua --check),
3. Emulator smoke check (if the milestone touches UI/runtime code),
4. Commit with a clear message.

## Lint and format

- Run `./dev.sh fmt` before committing; `./dev.sh lint` gates the milestone.
- Style is enforced by stylua (`.stylua.toml`, 4-space indent, 120 cols);
  do not hand-format around it.

## Porting rules

- The Lua core is a port of [rustoku](https://github.com/huangsam/rustoku)
  (MIT). Keep the pinned reference commit in README.md up to date and preserve
  attribution.
- Port its test data (HoDoKu examples) along with the techniques.
- The port extends rustoku with pattern metadata on solve steps to power the
  hint system; keep this divergence documented in PLAN.md.

## Repository layout

- `sudoku.koplugin/` — plugin source (deployed as-is to the device).
- `tests/unit/` — busted specs, symlinked into the (gitignored) koreader
  checkout's `spec/unit/` directory by the dev setup.
- `third_party/` — dev dependencies (koreader checkout, pinned rustoku clone),
  all gitignored.
