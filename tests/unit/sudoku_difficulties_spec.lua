package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path
local test_guard = require("sudoku_frontend_test_guard")
test_guard.install()

describe("sudoku difficulties", function()
    local difficulties
    setup(function()
        require("commonrequire")
        difficulties = require("ui.difficulties")
    end)

    it("lists all six difficulties in order", function()
        local list = difficulties.list()
        assert.are.same({ "beginner", "easy", "medium", "hard", "master", "expert" }, {
            list[1].id,
            list[2].id,
            list[3].id,
            list[4].id,
            list[5].id,
            list[6].id,
        })
        for _, entry in ipairs(list) do
            assert.is_string(entry.label)
            assert.is_true(#entry.label > 0, "labels must be non-empty")
        end
    end)

    it("returns localized labels for known difficulties", function()
        assert.are.equal("Beginner", difficulties.label("beginner"))
        assert.are.equal("Easy", difficulties.label("easy"))
        assert.are.equal("Medium", difficulties.label("medium"))
        assert.are.equal("Hard", difficulties.label("hard"))
        assert.are.equal("Master", difficulties.label("master"))
        assert.are.equal("Expert", difficulties.label("expert"))
        assert.are.equal("Custom", difficulties.label("custom"))
    end)

    it("formats display strings for standard and custom difficulties", function()
        assert.are.equal("Medium", difficulties.format_display("medium"))
        assert.are.equal("Custom", difficulties.format_display("custom"))
        assert.are.equal("Custom (Master)", difficulties.format_display("custom", "master"))
        assert.are.equal("Custom (Expert)", difficulties.format_display("custom", "expert"))
    end)

    it("returns nil for unknown difficulties", function()
        assert.is_nil(difficulties.label("insane"))
        assert.is_nil(difficulties.label(nil))
    end)
end)
