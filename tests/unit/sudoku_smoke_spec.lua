package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local meta = require("_meta")
local sudoku = require("core.sudoku")

describe("sudoku test harness", function()
    it("loads the plugin metadata with single-source-of-truth version", function()
        assert.is_table(meta)
        assert.are.equal("sudokuplus", meta.name)
        assert.is_string(meta.fullname)
        assert.is_string(meta.description)
        assert.is_string(meta.version)
        assert.is_not_nil(meta.version:match("^%d+%.%d+%.%d+$"))
    end)

    it("loads the plugin core facade", function()
        assert.is_table(sudoku)
        assert.is_function(sudoku.solve_any)
    end)
end)
