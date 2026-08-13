package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

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
    end)

    it("returns nil for unknown difficulties", function()
        assert.is_nil(difficulties.label("insane"))
        assert.is_nil(difficulties.label(nil))
    end)
end)
