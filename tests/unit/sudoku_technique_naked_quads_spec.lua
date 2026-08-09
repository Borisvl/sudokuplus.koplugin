package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local masks = require("core.masks")
local propagator = require("core.techniques.propagator")
local naked_quads = require("core.techniques.naked_quads")

-- HoDoKu naked quad example: https://hodoku.sourceforge.net/en/show_example.php?file=n401&tech=Naked+Quad
local HODOKU = "000000060000030047032500000600007005207010908081004000000002000000000001005870000"
local techniques = bit.bor(flags.EASY, flags.NAKED_QUADS)

-- Isolated row-0 propagator for direct detector tests. Cells (0,0)-(0,3) are
-- filled; (0,4)-(0,8) carry the masks under test.
local function row0_propagator(cell_masks)
    local b = board.new()
    for col = 0, 3 do
        board.set(b, 0, col, col + 6)
    end
    local cand = candidates.new()
    for col = 4, 8 do
        cand[1][col + 1] = cell_masks[col]
    end
    return propagator.new(b, masks.new(), cand, flags.NAKED_QUADS)
end

local function in_unit(unit, r, c)
    if unit.type == "row" then
        return r == unit.index
    elseif unit.type == "col" then
        return c == unit.index
    end
    local br = math.floor(unit.index / 3) * 3
    local bc = (unit.index % 3) * 3
    return r >= br and r < br + 3 and c >= bc and c < bc + 3
end

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function is_pattern_value(pattern, v)
    for _, value in ipairs(pattern.values) do
        if value == v then
            return true
        end
    end
    return false
end

local function quad_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.NAKED_QUADS then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.naked_quads", function()
    it("produces naked quad eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = quad_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata for the quad", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(quad_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("naked_quad", pattern.kind)
            assert.are.equal(4, #pattern.cells)
            assert.are.equal(4, #pattern.values)
            assert.is_not_nil(pattern.unit)
            for i = 1, 3 do
                assert.is_true(pattern.values[i] < pattern.values[i + 1])
            end
        end
    end)

    it("eliminates only the quad values from other cells of the unit", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(quad_steps(path)) do
            local pattern = step.pattern
            assert.is_true(in_unit(pattern.unit, step.row, step.col))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
            assert.is_true(is_pattern_value(pattern, step.value))
        end
    end)

    it("does not alter the givens", function()
        local original = board.from_string(HODOKU)
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for r = 0, 8 do
            for c = 0, 8 do
                local orig = board.get(original, r, c)
                if orig ~= 0 then
                    assert.are.equal(orig, board.get(s.board, r, c))
                end
            end
        end
    end)

    it("solves the example guess-free with easy techniques", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.are.equal(81, board.count_clues(s.board))
        assert.is_not_nil(solver.validate(s.board))
    end)

    it("finds a naked quad that includes a singleton cell", function()
        -- (0,6)={3} is a singleton; (0,5)={1,2}, (0,7)={1,4}, (0,8)={2,3,4}
        -- confine {1,2,3,4} to four cells, so the union is eliminated from
        -- the rest of the row. The old code skipped 1-candidate cells.
        local p = row0_propagator({
            [4] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 4)),
            [5] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [6] = bit.lshift(1, 2),
            [7] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 3)),
            [8] = bit.bor(bit.lshift(1, 1), bit.bor(bit.lshift(1, 2), bit.lshift(1, 3))),
        })
        local path = solve_path.new()

        assert.is_true(naked_quads.apply(p, path))
        assert.are.equal(bit.lshift(1, 4), p:cand(0, 4), "the quad digits are eliminated from the peer cell")
    end)

    it("does not treat four cells confined to three digits as a naked quad", function()
        -- (0,4)-(0,7) all hold only {1,2,3}: the union has three digits, so no
        -- four-cell combo is a quad (eliminating would be unsound).
        local p = row0_propagator({
            [4] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
            [5] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
            [6] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
            [7] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
            [8] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
        })
        local path = solve_path.new()

        assert.is_false(naked_quads.apply(p, path))
    end)
end)
