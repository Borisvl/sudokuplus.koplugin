package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

describe("sudoku localization", function()
    local _
    local N_
    local T
    local hints
    local techniques
    local messages
    local difficulties
    local status
    local Sudoku

    setup(function()
        require("commonrequire")
        _ = require("gettext")
        N_ = _.ngettext
        T = require("ffi/util").template
        hints = require("core.hints")
        techniques = require("ui.techniques")
        messages = require("ui.messages")
        difficulties = require("ui.difficulties")
        status = require("ui.status")
        Sudoku = require("main")
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

    describe("German PO/MO translation catalog", function()
        local saved_translation
        local saved_context
        local saved_getPlural
        local saved_current_lang
        local saved_G_reader_settings

        before_each(function()
            saved_translation = _.translation
            saved_context = _.context
            saved_getPlural = _.getPlural
            saved_current_lang = _.current_lang
            saved_G_reader_settings = _G.G_reader_settings

            _.translation = {}
            _.context = {}
            -- Explicit dummy plural function to verify that loadMO parses the header
            _.getPlural = function()
                return -1
            end
        end)

        after_each(function()
            _.translation = saved_translation
            _.context = saved_context
            _.getPlural = saved_getPlural
            _.current_lang = saved_current_lang
            _G.G_reader_settings = saved_G_reader_settings
        end)

        it("loads and applies German translations from sudoku.mo and parses plural headers", function()
            local mo_path = "plugins/sudoku.koplugin/l10n/de/sudoku.mo"
            local loaded = _.loadMO(mo_path)
            assert.is_true(loaded, "German MO file should load cleanly")

            -- Verify header was parsed and plural function was compiled
            assert.are.equal(0, _.getPlural(1))
            assert.are.equal(1, _.getPlural(0))
            assert.are.equal(1, _.getPlural(2))

            -- Techniques
            assert.are.equal("Nackte Einer", techniques.label("naked_singles"))
            assert.are.equal("Versteckte Einer", techniques.label("hidden_singles"))
            assert.are.equal("Gesperrte Kandidaten", techniques.label("locked_candidates"))
            assert.are.equal("Alternierende Inferenzkette", techniques.label("aic"))

            -- Difficulties
            assert.are.equal("Anfänger", difficulties.label("beginner"))
            assert.are.equal("Leicht", difficulties.label("easy"))
            assert.are.equal("Mittel", difficulties.label("medium"))
            assert.are.equal("Schwer", difficulties.label("hard"))
            assert.are.equal("Meister", difficulties.label("master"))
            assert.are.equal("Experte", difficulties.label("expert"))

            -- Status
            assert.are.equal("Laufend", status.label("in_progress"))
            assert.are.equal("Beendet", status.label("finished"))
            assert.are.equal("Aufgegeben", status.label("give_up"))
            assert.are.equal("Abgebrochen", status.label("abandoned"))

            -- Messages
            assert.are.equal(
                "Vorgegebene Zelle kann nicht geändert werden.",
                messages.translate("cannot modify a given cell")
            )
            assert.are.equal(
                "Das Spielfeld wurde seit Erstellung des Tipps verändert.",
                messages.translate("action is stale")
            )

            -- Plural forms
            assert.are.equal("1 falsche Zelle gefunden.", T(N_("1 wrong cell found.", "%1 wrong cells found.", 1), 1))
            assert.are.equal("3 falsche Zellen gefunden.", T(N_("1 wrong cell found.", "%1 wrong cells found.", 3), 3))
        end)

        it("loads German MO via main.lua when KOReader language setting is de_DE and current_lang is C", function()
            _.current_lang = "C"
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "language" then
                        return "de_DE"
                    end
                end,
            }

            Sudoku:new {
                path = "plugins/sudoku.koplugin",
                ui = {
                    menu = {
                        registerToMainMenu = function() end,
                    },
                },
            }

            assert.are.equal("Nackte Einer", techniques.label("naked_singles"))
            assert.are.equal("Anfänger", difficulties.label("beginner"))
            assert.are.equal("Erneut spielen", _("Play again"))
        end)
    end)
end)
