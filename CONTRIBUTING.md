# Contributing to Sudoku+

Thank you for your interest in contributing to **Sudoku+**! We welcome bug fixes, performance improvements, new solving techniques, documentation enhancements, and translations.

---

## 🛠️ Development Setup

Sudoku+ is developed against the [KOReader](https://github.com/koreader/koreader) environment.

### Prerequisites (macOS / Linux)

- **LuaJIT** / **Lua 5.1**
- **Luacheck** (`luarocks install luacheck` or `brew install luacheck`)
- **StyLua** (`cargo install stylua` or `brew install stylua`)
- **gettext** (`brew install gettext` or `sudo apt-get install gettext`)
- KOReader development dependencies (see [KOReader Developer Guide](https://github.com/koreader/koreader/blob/master/doc/Building.md))

### Quickstart

1. Clone this repository:
   ```sh
   git clone https://github.com/Borisvl/sudokuplus.koplugin.git
   cd sudokuplus.koplugin
   ```
2. Fetch and build the local KOReader dev environment:
   ```sh
   git clone https://github.com/koreader/koreader.git third_party/koreader
   cd third_party/koreader
   source ../../env.sh
   ./kodev fetch-thirdparty
   ./kodev build
   cd ../..
   ```
3. Launch the emulator:
   ```sh
   ./dev.sh
   ```

---

## 🧪 Testing & Code Discipline

### Test-First Policy
We follow a strict **test-first discipline**:
- `sudokuplus.koplugin/core/` is **pure Lua** with **zero KOReader UI dependencies**. It must be fully unit-testable headless.
- Always write tests before implementing new features or fixing bugs.
- PRs without tests for new logic will not be merged.

### Running Tests
Headless unit tests live in `tests/unit/*_spec.lua` and run via the busted harness:

```sh
# Run all plugin specs
./dev.sh test

# Run a specific spec
./dev.sh test tests/unit/sudoku_hints_spec.lua

# Filter tests by describe/it block name
./dev.sh test -f "skyscraper"
```

### Linting & Formatting
Code style is strictly enforced via [StyLua](https://github.com/JohnnyMorganz/StyLua) (4-space indent, 120-column limit) and [Luacheck](https://github.com/lunarmodules/luacheck):

```sh
# Check linting and formatting
./dev.sh lint

# Auto-format codebase
./dev.sh fmt
```

Before submitting a Pull Request, verify that:
1. `./dev.sh test` passes all tests.
2. `./dev.sh lint` reports **0 warnings / 0 errors**.

---

## 🌐 Localization & Translations (i18n)

We want Sudoku+ to be accessible in every language KOReader supports!

### Adding or Updating a Translation

1. Extract the latest translatable strings:
   ```sh
   ./dev.sh pot
   ```
2. Create or edit the PO file for your language (e.g. French in `sudokuplus.koplugin/l10n/fr/sudokuplus.po`):
   ```sh
   mkdir -p sudokuplus.koplugin/l10n/fr
   msginit --input=sudokuplus.koplugin/l10n/sudokuplus.pot \
           --output=sudokuplus.koplugin/l10n/fr/sudokuplus.po \
           --locale=fr_FR
   ```
3. Translate the strings in your favorite PO editor (such as Poedit or a plain text editor).
4. Run `./dev.sh pot` again to compile `.po` into `.mo`.
5. Test your translation in the emulator or by submitting a PR!

---

## 📦 Packaging a Release

To test building the standalone release zip package:
```sh
./tools/package_release.sh
```
This generates a clean `dist/sudokuplus.koplugin.zip` ready for device installation.
