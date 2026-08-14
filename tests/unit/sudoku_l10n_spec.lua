package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku localization", function()
    local hints
    local techniques
    local messages
    local difficulties
    local status

    setup(function()
        require("commonrequire")
        hints = require("core.hints")
        techniques = require("ui.techniques")
        messages = require("ui.messages")
        difficulties = require("ui.difficulties")
        status = require("ui.status")
    end)

    describe("techniques localization", function()
        it("maps every technique in core hints to a localized non-empty label", function()
            local core_techniques = hints.techniques()
            assert.are.equal(17, #core_techniques)
            for _, t in ipairs(core_techniques) do
                local label = techniques.label(t.id)
                assert.is_string(label)
                assert.is_true(#label > 0, "label for " .. t.id .. " must be non-empty")
                assert.is_not_equal(t.id, label, "label should be formatted/translated, not raw id")
            end
        end)

        it("translates canonical English technique names", function()
            assert.are.equal("Naked Singles", techniques.label("naked_singles"))
            assert.are.equal("Alternating Inference Chain", techniques.label("aic"))
            assert.are.equal("Locked Candidates", techniques.label("locked_candidates"))
            assert.are.equal("Skyscraper", techniques.label("skyscraper"))
        end)

        it("falls back to the raw input for unknown technique IDs", function()
            assert.are.equal("custom_technique", techniques.label("custom_technique"))
            assert.is_nil(techniques.label(nil))
        end)
    end)

    describe("messages localization", function()
        it("maps all registered engine and game errors to non-empty translations", function()
            local keys = messages.keys()
            assert.is_true(#keys >= 10, "messages must map all domain error strings")
            for _, key in ipairs(keys) do
                local translated = messages.translate(key)
                assert.is_string(translated)
                assert.is_true(#translated > 0)
                assert.is_not_equal(key, translated)
            end
        end)

        it("translates critical game error messages", function()
            assert.are.equal("Cannot modify a given cell.", messages.translate("cannot modify a given cell"))
            assert.are.equal(
                "The board has changed since this hint was generated.",
                messages.translate("action is stale")
            )
            assert.are.equal(
                "The board has conflicts. Fix them before asking for a hint.",
                messages.translate("board has conflicts")
            )
        end)

        it("falls back to the raw message for unknown strings", function()
            assert.are.equal("some unknown error", messages.translate("some unknown error"))
            assert.is_nil(messages.translate(nil))
        end)
    end)

    describe("dynamic difficulty translation", function()
        it("returns localized labels for all difficulties", function()
            local list = difficulties.list()
            assert.are.equal(6, #list)
            for _, item in ipairs(list) do
                assert.is_string(item.label)
                assert.is_true(#item.label > 0)
                assert.are.equal(item.label, difficulties.label(item.id))
            end
        end)
    end)

    describe("status localization", function()
        it("returns localized labels for all game statuses", function()
            local statuses = { "in_progress", "finished", "give_up", "abandoned" }
            for _, s in ipairs(statuses) do
                local label = status.label(s)
                assert.is_string(label)
                assert.is_true(#label > 0)
                assert.is_not_equal(s, label)
            end
            assert.are.equal("In progress", status.label("in_progress"))
            assert.are.equal("custom_status", status.label("custom_status"))
            assert.is_nil(status.label(nil))
        end)
    end)

    describe("POT catalog coverage", function()
        it("contains all critical gettext msgids in plugins/sudoku.koplugin/l10n/sudoku.pot", function()
            local file = io.open("plugins/sudoku.koplugin/l10n/sudoku.pot", "rb")
                or io.open("sudoku.koplugin/l10n/sudoku.pot", "rb")
            assert.is_not_nil(file, "sudoku.pot must exist and be readable")
            local content = file:read("*a")
            file:close()

            local required_msgids = {
                "Sudoku",
                "A Sudoku puzzle game for e-ink readers.",
                "Beginner",
                "Easy",
                "Medium",
                "Hard",
                "Master",
                "Expert",
                "Naked Singles",
                "Alternating Inference Chain",
                "Locked Candidates",
                "Skyscraper",
                "Undo",
                "Redo",
                "Notes",
                "Check",
                "Hint",
                "Menu",
                "Cannot modify a given cell.",
                "1 wrong cell found.",
                "Sudoku statistics",
            }

            for _, msgid in ipairs(required_msgids) do
                assert.is_truthy(content:find('msgid "' .. msgid .. '"', 1, true), "POT file missing msgid: " .. msgid)
            end
        end)
    end)
end)
