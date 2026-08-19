package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

describe("sudoku help module", function()
    local help
    local UIManager

    setup(function()
        require("commonrequire")
        help = require("ui.help")
        UIManager = require("ui/uimanager")
    end)

    it("defines the main help topics including about", function()
        local topics = help.topics()
        assert.is_table(topics)
        assert.are.equal(3, #topics)
        assert.are.equal("controls", topics[1].id)
        assert.is_string(topics[1].title)
        assert.is_string(topics[1].summary)
        assert.are.equal("features", topics[2].id)
        assert.is_string(topics[2].title)
        assert.is_string(topics[2].summary)
        assert.are.equal("about", topics[3].id)
        assert.is_string(topics[3].title)
        assert.is_string(topics[3].summary)
    end)

    it("returns formatted text for the controls topic", function()
        local text = help.get_text("controls")
        assert.is_string(text)
        assert.is_true(#text > 100)
        assert.is_not_nil(text:find("### Goal & Basic Rules", 1, true))
        assert.is_not_nil(text:find("### Number-First Input (Pen Mode)", 1, true))
        assert.is_not_nil(text:find("- **Arm a digit:**", 1, true))
        assert.is_not_nil(text:find("*Notes*", 1, true))
        assert.is_not_nil(text:find("`~0.5s`", 1, true))
    end)

    it("returns formatted text for the features topic", function()
        local text = help.get_text("features")
        assert.is_string(text)
        assert.is_true(#text > 100)
        assert.is_not_nil(text:find("### Progressive 3-Step Hints", 1, true))
        assert.is_not_nil(text:find("Naked Pairs and Locked Candidates", 1, true))
        assert.is_not_nil(text:find("Hidden Pairs, Naked Triples, and Hidden Triples", 1, true))
        assert.is_not_nil(text:find("X-Wing, Swordfish, Skyscraper", 1, true))
        assert.is_not_nil(text:find("AIC", 1, true))
        assert.is_not_nil(text:find("Custom Mode", 1, true))
    end)

    it("returns formatted text for the about topic", function()
        local meta = require("_meta")
        local text = help.get_text("about")
        assert.is_string(text)
        assert.is_true(#text > 50)
        assert.is_not_nil(text:find("### Sudoku+ for KOReader", 1, true))
        assert.is_not_nil(text:find(meta.version, 1, true))
        assert.is_not_nil(text:find("Boris von Loesch", 1, true))
        assert.is_not_nil(text:find("AGPL-3.0", 1, true))
        assert.is_not_nil(text:find("rustoku", 1, true))
        assert.is_not_nil(text:find("HoDoKu", 1, true))
    end)

    it("returns nil for unknown topic ids", function()
        assert.is_nil(help.get_text("nonexistent"))
    end)

    it("builds a help menu with items for all topics", function()
        local menu = help.menu()
        assert.is_not_nil(menu)
        assert.is_table(menu.item_table)
        assert.are.equal(3, #menu.item_table)
        assert.is_true(menu.item_table[1].text:find(help.topics()[1].title, 1, true) ~= nil)
        assert.is_true(menu.item_table[2].text:find(help.topics()[2].title, 1, true) ~= nil)
        assert.is_true(menu.item_table[3].text:find(help.topics()[3].title, 1, true) ~= nil)
    end)

    it("tapping a menu item opens a TextViewer with markdown text_format", function()
        local menu = help.menu()
        local shown_widget
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown_widget = widget
        end
        finally(function()
            UIManager.show = original_show
        end)

        menu.item_table[1].callback()
        assert.is_not_nil(shown_widget)
        assert.is_not_nil(shown_widget.text)
        assert.are.equal("md", shown_widget.text_format)
        assert.are.equal(help.get_text("controls"), shown_widget.text)
    end)

    it("show_topic directly presents the TextViewer with markdown text_format", function()
        local shown_widget
        local original_show = UIManager.show
        UIManager.show = function(_, widget)
            shown_widget = widget
        end
        finally(function()
            UIManager.show = original_show
        end)

        help.show_topic("features")
        assert.is_not_nil(shown_widget)
        assert.are.equal("md", shown_widget.text_format)
        assert.are.equal(help.get_text("features"), shown_widget.text)
    end)
end)
