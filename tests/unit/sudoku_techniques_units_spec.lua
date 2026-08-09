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

    it("finds units with a candidate count within a range", function()
        local b = board.new()
        local c = candidates.new()
        local one_bit = bit.lshift(1, 0)
        -- Row 0: candidates in columns 0 and 1 (count 2).
        candidates.set(c, 0, 0, one_bit)
        candidates.set(c, 0, 1, one_bit)
        -- Row 2: candidates in columns 3, 5, 7 (count 3).
        candidates.set(c, 2, 3, one_bit)
        candidates.set(c, 2, 5, one_bit)
        candidates.set(c, 2, 7, one_bit)

        local rows = units.find_units_with_candidate_count_range(one_bit, 2, 3, c, b, "row")
        assert.are.equal(2, #rows)
        assert.are.equal(0, rows[1][1])
        assert.are.same({ 0, 1 }, rows[1][2])
        assert.are.equal(2, rows[2][1])
        assert.are.same({ 3, 5, 7 }, rows[2][2])

        assert.are.equal(0, #units.find_units_with_candidate_count_range(one_bit, 4, 9, c, b, "row"))

        -- Filled cells are excluded: column 0 drops below the range, the rest stay.
        board.set(b, 0, 0, 1)
        local cols = units.find_units_with_candidate_count_range(one_bit, 1, 2, c, b, "col")
        assert.are.equal(4, #cols)
        local col_indices = {}
        for _, entry in ipairs(cols) do
            col_indices[entry[1]] = true
        end
        assert.is_nil(col_indices[0])
        assert.is_true(col_indices[1] and col_indices[3] and col_indices[5] and col_indices[7])
    end)

    it("sees cells sharing a row, column, or box", function()
        assert.is_true(units.sees(2, 3, 2, 7))
        assert.is_true(units.sees(2, 3, 5, 3))
        assert.is_true(units.sees(2, 3, 1, 4))
        assert.is_true(units.sees(2, 3, 2, 3))
        assert.is_false(units.sees(2, 3, 5, 6))
        assert.is_false(units.sees(0, 4, 4, 7))
    end)

    it("iterates all combinations of size k from 1..n", function()
        local combos = {}
        units.for_each_combination(4, 2, function(combo)
            combos[#combos + 1] = { combo[1], combo[2] }
        end)
        assert.are.same({ { 1, 2 }, { 1, 3 }, { 1, 4 }, { 2, 3 }, { 2, 4 }, { 3, 4 } }, combos)

        local combos4 = {}
        units.for_each_combination(9, 4, function(combo)
            combos4[#combos4 + 1] = combo
        end)
        assert.are.equal(126, #combos4)
        for _, combo in ipairs(combos4) do
            assert.are.equal(4, #combo)
            assert.is_true(combo[1] < combo[2] and combo[2] < combo[3] and combo[3] < combo[4])
        end
    end)

    it("yields no combinations when n < k or k == 0", function()
        local count = 0
        units.for_each_combination(2, 4, function()
            count = count + 1
        end)
        assert.are.equal(0, count)
        units.for_each_combination(0, 0, function()
            count = count + 1
        end)
        assert.are.equal(0, count)
    end)

    it("passes fresh tables that can be retained by the callback", function()
        local retained = {}
        units.for_each_combination(3, 2, function(combo)
            retained[#retained + 1] = combo
        end)
        for _, combo in ipairs(retained) do
            assert.are.equal(2, #combo)
        end
    end)

    it("lists bivalue cells with their candidate masks", function()
        local b = board.new()
        local c = candidates.new()
        local bit1 = bit.lshift(1, 0)
        local bit2 = bit.lshift(1, 1)
        local bit3 = bit.lshift(1, 2)
        candidates.set(c, 1, 1, bit.bor(bit1, bit2))
        candidates.set(c, 3, 5, bit.bor(bit2, bit3))
        candidates.set(c, 7, 0, bit.bor(bit1, bit2, bit3))
        board.set(b, 0, 0, 1)

        local bivalue = units.bivalue_cells(c, b)
        assert.are.equal(2, #bivalue)
        assert.are.same({ 1, 1 }, { bivalue[1][1], bivalue[1][2] })
        assert.are.equal(bit.bor(bit1, bit2), bivalue[1][3])
        assert.are.same({ 3, 5 }, { bivalue[2][1], bivalue[2][2] })
        assert.are.equal(bit.bor(bit2, bit3), bivalue[2][3])
    end)

    it("lists all peers of a cell exactly once", function()
        local peers = units.peers_of(4, 4)
        local seen = {}
        for _, cell in ipairs(peers) do
            local key = cell[1] .. "," .. cell[2]
            assert.is_nil(seen[key], "duplicate peer " .. key)
            seen[key] = true
            assert.is_true(units.sees(4, 4, cell[1], cell[2]))
            assert.is_false(cell[1] == 4 and cell[2] == 4)
        end
        -- row (8) + col (8) + box-only cells (4), excluding self.
        assert.are.equal(20, #peers)
        assert.is_true(seen["4,0"])
        assert.is_true(seen["0,4"])
        assert.is_true(seen["3,3"])
        assert.is_true(seen["5,5"])
        assert.is_nil(seen["0,0"])
    end)

    it("each_peer visits exactly the same peers as peers_of, without a list", function()
        local peers = units.peers_of(2, 6)
        local visited = {}
        units.each_peer(2, 6, function(r, c)
            visited[#visited + 1] = { r, c }
        end)
        assert.are.equal(#peers, #visited, "each_peer must visit every peer")
        for _, cell in ipairs(peers) do
            local found = false
            for _, other in ipairs(visited) do
                if other[1] == cell[1] and other[2] == cell[2] then
                    found = true
                    break
                end
            end
            assert.is_true(found, "each_peer missed peer " .. cell[1] .. "," .. cell[2])
        end
    end)
end)
