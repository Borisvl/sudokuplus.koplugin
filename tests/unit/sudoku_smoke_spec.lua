package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local metadata = require("sudokuplus.metadata")
local meta = dofile("plugins/sudokuplus.koplugin/_meta.lua")
local sudoku = require("sudokuplus.core.sudoku")

describe("sudoku test harness", function()
    it("loads the plugin metadata with single-source-of-truth version", function()
        assert.is_table(meta)
        assert.are.equal(metadata.name, meta.name)
        assert.are.equal(metadata.version, meta.version)
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
