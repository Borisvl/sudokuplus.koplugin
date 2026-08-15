local Device = require("device")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local meta = require("_meta")

local Screen = Device.screen

local help = {}

local TOPIC_DEFS = {
    {
        id = "controls",
        title_fn = function()
            return _("How to play & controls")
        end,
        summary_fn = function()
            return _("Objective, number-first pen mode, notes, gestures, and hardware keys.")
        end,
    },
    {
        id = "features",
        title_fn = function()
            return _("Features, hints & tools")
        end,
        summary_fn = function()
            return _("Progressive hints, mistake checking, auto-clean, difficulties, and statistics.")
        end,
    },
    {
        id = "about",
        title_fn = function()
            return _("About & Credits")
        end,
        summary_fn = function()
            return _("Version, license, credits, and acknowledgments.")
        end,
    },
}

function help.topics()
    local list = {}
    for i, def in ipairs(TOPIC_DEFS) do
        list[i] = {
            id = def.id,
            title = def.title_fn(),
            summary = def.summary_fn(),
        }
    end
    return list
end

function help.topic_title(id)
    for _, def in ipairs(TOPIC_DEFS) do
        if def.id == id then
            return def.title_fn()
        end
    end
    return nil
end

function help.get_text(topic_id)
    if topic_id == "controls" then
        return table.concat({
            _("### Goal & Basic Rules"),
            "",
            _("Fill the 9×9 grid so that every row, column, and 3×3 box contains digits 1 to 9 with no duplicates."),
            "",
            _("### Number-First Input (Pen Mode)"),
            "",
            _("- **Arm a digit:** Tap any number (1–9) on the bottom bar. The button inverts to show it is armed."),
            _("- **Place digit:** Tap an empty cell on the board to write the armed digit."),
            _("- **Erase digit:** Tap a cell already containing the armed digit to erase it."),
            _("- **Replace digit:** Tap a cell containing a different number to replace it."),
            _("- **Disarm:** Tap the armed number button again to return to neutral selection mode."),
            _("- **Selection mode:** When no digit is armed, tapping a cell selects it without altering the board."),
            "",
            _("### Pencil Marks & Notes Mode"),
            "",
            _("- **Toggle Notes:** Tap the *Notes* button in the tool row to toggle pencil marks mode."),
            _("- **Adding notes:** With Notes mode **ON**, tapping a cell with an armed digit toggles that note."),
            "",
            _("### Quick Mode-Flip Gesture"),
            "",
            _("- **Long-press (`~0.5s`):** Holding a cell while a digit is armed temporarily inverts the mode:"),
            _("  - *Notes mode OFF:* Long-press writes/toggles a pencil mark note."),
            _("  - *Notes mode ON:* Long-press places a permanent number."),
            "",
            _("### Matching Digit Highlights"),
            "",
            _("- Arming a digit or selecting a cell highlights all matching digits and notes across the board."),
            "",
            _("### Hardware Key Shortcuts (Kobo & E-Readers)"),
            "",
            _("- **Short press page turn / arrow keys:** Cycles digits 1–9. Completed digits are skipped!"),
            _("- **Hold page turn / arrow key (`≥ 0.5s`):** Toggles Notes mode on/off without touching the screen."),
        }, "\n")
    elseif topic_id == "features" then
        return table.concat({
            _("### Progressive 3-Step Hints"),
            "",
            _("Tap the *Hint* button in the toolbar for progressive, step-by-step assistance:"),
            "",
            _("- **Step 1 (Strategy Name):** Displays the next solving technique banner (e.g. *Naked Pair*)."),
            _("- **Step 2 (Visual Clue):** Highlights pattern cells and eliminations directly on the board."),
            _("- **Step 3 (Apply):** Applies the logical deduction to the board or candidate notes."),
            _("- *Note:* Requesting a hint is recorded in your statistics as an overlooked strategy."),
            "",
            _("### Mistake Checking & Conflicts"),
            "",
            _("- **Live Conflicts:** Immediate dark highlight on duplicate numbers violating row, col, or box rules."),
            _("- **Check Board:** Tapping *Check* compares with solution and marks wrong entries with strikethrough."),
            "",
            _("### Smart Auto-Clean & Bulk Notes"),
            "",
            _("- **Auto-clean:** Placing a number removes candidate from peers. Erase/undo restores previous notes."),
            _("- **Auto-fill notes setting:** Starts new games with legal pencil marks pre-populated (in *Tools*)."),
            _("- **Fill all notes:** Populates all remaining legal notes at any time from the pause Menu."),
            "",
            _("### Undo, Redo & Reset"),
            "",
            _("- Full undo/redo history for digit placements, note edits, and hint actions."),
            _("- **Reset puzzle:** Restarts the current puzzle from the beginning via the pause Menu."),
            "",
            _("### Difficulty Tiers"),
            "",
            _("- **Beginner:** Pure singles, 38+ initial clues."),
            _("- **Easy:** Pure singles, under 38 clues."),
            _("- **Medium:** Introduces Naked Pairs and Locked Candidates."),
            _("- **Hard:** Introduces Hidden Pairs, Naked Triples, and Hidden Triples."),
            _("- **Master:** Introduces X-Wing, Skyscraper, Naked Quads, and Wings (XY, XYZ, W-Wing)."),
            _("- **Expert:** Introduces Hidden Quads, Swordfish, Jellyfish, and AIC."),
            "",
            _("### Statistics & Game History"),
            "",
            _("- Track completion rates, streaks, best/average times, and overlooked strategies in *Statistics*."),
            _("- Review and replay past puzzles from the *Game history* log."),
        }, "\n")
    elseif topic_id == "about" then
        return table.concat({
            _("### Sudoku+ for KOReader"),
            "",
            _("A logical Sudoku puzzle game and interactive tutor crafted specifically for e-ink readers."),
            "",
            T(_("- **Version:** %1"), meta.version or "1.0.0"),
            T(_("- **Copyright:** %1"), "© 2026 Boris von Loesch and contributors"),
            T(_("- **License:** %1"), "GNU Affero General Public License v3.0 (AGPL-3.0)"),
            T(_("- **Repository:** %1"), "https://github.com/Borisvl/sudokuplus.koplugin"),
            "",
            _("### Credits & Attribution"),
            "",
            _(
                "- **Logical Solver & Generator:** Core algorithms and human deduction"
                    .. " techniques are ported from **rustoku** by Samuel Huang (MIT License)."
            ),
            _(
                "- **Techniques & Test Datasets:** Technique taxonomies and benchmark"
                    .. " puzzles are derived from the **HoDoKu** project by Bernhard Hobiger."
            ),
            _("- **Platform:** Built for **KOReader** and its e-ink reading community."),
        }, "\n")
    end
    return nil
end

function help.show_topic(topic_id)
    local title = help.topic_title(topic_id)
    if not title then
        return
    end
    local topic_text = help.get_text(topic_id)
    if not topic_text then
        return
    end
    local viewer = TextViewer:new {
        title = title,
        text = topic_text,
        text_format = "md",
    }
    UIManager:show(viewer, "full")
    return viewer
end

function help.menu()
    local items = {}
    for _, topic in ipairs(help.topics()) do
        items[#items + 1] = {
            text = topic.title,
            callback = function()
                help.show_topic(topic.id)
            end,
        }
    end

    return Menu:new {
        title = _("Sudoku+ Help"),
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
end

function help.show_menu()
    local menu_widget = help.menu()
    UIManager:show(menu_widget, "full")
    return menu_widget
end

return help
