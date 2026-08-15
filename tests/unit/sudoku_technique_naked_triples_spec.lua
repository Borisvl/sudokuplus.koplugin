package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local masks = require("core.masks")
local propagator = require("core.techniques.propagator")
local naked_triples = require("core.techniques.naked_triples")

-- HoDoKu naked triple example: https://hodoku.sourceforge.net/en/show_example.php?file=l302&tech=Locked+Triple
local HODOKU = "400500370320000004060000000800002030210840000000000090070090100040651000000070000"
local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.NAKED_TRIPLES)

-- Isolated row-0 propagator for direct detector tests. Cells (0,0)-(0,4) are
-- filled; (0,5)-(0,8) carry the masks under test.
local function row0_propagator(cell_masks)
    local b = board.new()
    for col = 0, 4 do
        board.set(b, 0, col, col + 5)
    end
    local cand = candidates.new()
    for col = 5, 8 do
        cand[1][col + 1] = cell_masks[col]
    end
    return propagator.new(b, masks.new(), cand, flags.NAKED_TRIPLES)
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

local function triple_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.NAKED_TRIPLES then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.naked_triples", function()
    it("produces naked triple eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = triple_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata for the triple", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(triple_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("naked_triple", pattern.kind)
            assert.are.equal(3, #pattern.cells)
            assert.are.equal(3, #pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_true(pattern.values[1] < pattern.values[2] and pattern.values[2] < pattern.values[3])
        end
    end)

    it("eliminates only the triple values from other cells of the unit", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(triple_steps(path)) do
            local pattern = step.pattern
            assert.is_true(in_unit(pattern.unit, step.row, step.col))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
            local in_values = step.value == pattern.values[1]
                or step.value == pattern.values[2]
                or step.value == pattern.values[3]
            assert.is_true(in_values)
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

    it("finds a naked triple that includes a singleton cell", function()
        -- (0,6)={1} is a singleton; together with (0,7)={2,3} and (0,8)={1,2,3}
        -- it confines {1,2,3} to three cells, so the union is eliminated from
        -- the rest of the row. The old code skipped 1-candidate cells and
        -- missed this.
        local p = row0_propagator({
            [5] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 3)),
            [6] = bit.lshift(1, 0),
            [7] = bit.bor(bit.lshift(1, 1), bit.lshift(1, 2)),
            [8] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 2))),
        })
        local path = solve_path.new()

        assert.is_true(naked_triples.apply(p, path))
        assert.are.equal(bit.lshift(1, 3), p:cand(0, 5), "the triple digits are eliminated from the peer cell")
        assert.are.equal(bit.lshift(1, 0), p:cand(0, 6))
        assert.are.equal(bit.bor(bit.lshift(1, 1), bit.lshift(1, 2)), p:cand(0, 7))
    end)

    it("does not treat three cells confined to two digits as a naked triple", function()
        -- (0,5)-(0,7) all hold only {1,2}: the union has two digits, so any
        -- three cells are not a triple (and eliminating would be unsound).
        local p = row0_propagator({
            [5] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [6] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [7] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [8] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
        })
        local path = solve_path.new()

        assert.is_false(naked_triples.apply(p, path))
    end)
end)
