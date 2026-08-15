package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local sudoku = require("core.sudoku")

describe("sudoku test harness", function()
    it("loads the plugin core facade", function()
        assert.is_table(sudoku)
        assert.is_function(sudoku.solve_any)
    end)
end)
