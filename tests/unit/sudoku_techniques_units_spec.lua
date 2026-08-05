package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local units = require("core.techniques.units")

describe("core.techniques.units", function()
    it("lists row cells in column order", function()
        local cells = units.row_cells(5)
        assert.are.equal(9, #cells)
        for c = 0, 8 do
            assert.are.same({ 5, c }, cells[c + 1])
        end
    end)

    it("lists column cells in row order", function()
        local cells = units.col_cells(3)
        assert.are.equal(9, #cells)
        for r = 0, 8 do
            assert.are.same({ r, 3 }, cells[r + 1])
        end
    end)

    it("lists box cells row-major within the box", function()
        local box0 = units.box_cells(0)
        assert.are.same({ 0, 0 }, box0[1])
        assert.are.same({ 1, 1 }, box0[5])
        assert.are.same({ 2, 2 }, box0[9])

        local box4 = units.box_cells(4)
        assert.are.same({ 3, 3 }, box4[1])
        assert.are.same({ 4, 4 }, box4[5])
        assert.are.same({ 5, 5 }, box4[9])

        local box8 = units.box_cells(8)
        assert.are.same({ 6, 6 }, box8[1])
        assert.are.same({ 7, 7 }, box8[5])
        assert.are.same({ 8, 8 }, box8[9])
    end)

    it("provides shared immutable unit descriptors", function()
        assert.are.same({ type = "row", index = 3 }, units.row_unit(3))
        assert.are.same({ type = "col", index = 5 }, units.col_unit(5))
        assert.are.same({ type = "box", index = 7 }, units.box_unit(7))
        assert.is_true(units.row_unit(3) == units.row_unit(3))
        assert.is_true(units.col_unit(5) == units.col_unit(5))
        assert.is_true(units.box_unit(7) == units.box_unit(7))
    end)

    it("iterates every unit in rows, columns, boxes order", function()
        local seen = {}
        units.for_each_unit(function(unit, cells)
            assert.are.equal(9, #cells)
            seen[#seen + 1] = unit.type .. unit.index
        end)
        assert.are.equal(27, #seen)
        local expected = {}
        for r = 0, 8 do
            expected[#expected + 1] = "row" .. r
        end
        for c = 0, 8 do
            expected[#expected + 1] = "col" .. c
        end
        for b = 0, 8 do
            expected[#expected + 1] = "box" .. b
        end
        assert.are.same(expected, seen)
    end)

    it("finds units with exactly n occurrences of a candidate", function()
        local b = board.new()
        local c = candidates.new()
        local one_bit = bit.lshift(1, 0)
        candidates.set(c, 0, 0, one_bit)
        candidates.set(c, 0, 1, one_bit)

        local rows = units.find_units_with_n_candidates(one_bit, 2, c, b, "row")
        assert.are.equal(1, #rows)
        assert.are.equal(0, rows[1][1])
        assert.are.same({ 0, 1 }, rows[1][2])

        local cols = units.find_units_with_n_candidates(one_bit, 1, c, b, "col")
        assert.are.equal(2, #cols)
        assert.are.equal(0, cols[1][1])
        assert.are.equal(1, cols[2][1])

        assert.are.equal(0, #units.find_units_with_n_candidates(one_bit, 3, c, b, "row"))

        board.set(b, 0, 0, 1)
        local rows_after = units.find_units_with_n_candidates(one_bit, 1, c, b, "row")
        assert.are.equal(1, #rows_after)
        assert.are.equal(0, rows_after[1][1])
        assert.are.same({ 1 }, rows_after[1][2])
    end)
end)
