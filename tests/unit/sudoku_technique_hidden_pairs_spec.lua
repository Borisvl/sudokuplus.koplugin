package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local masks = require("core.masks")
local propagator = require("core.techniques.propagator")
local hidden_pairs = require("core.techniques.hidden_pairs")

-- HoDoKu hidden pair example: https://hodoku.sourceforge.net/en/show_example.php?file=h201&tech=Hidden+Pair
local HODOKU = "000032000000000000007600914096000800005008000030040005050200000700000560904010000"
local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.HIDDEN_PAIRS)

-- Isolated row-0 propagator for direct detector tests. Only the row-0 cells in
-- `empty_masks` (col -> candidate mask) are empty; every other cell is filled,
-- so row 0 is the only unit able to host a multi-cell pattern (and the empty
-- cells are spread across distinct boxes/columns so no box-level pair forms).
local function row0_propagator(empty_masks)
    local b = board.new()
    for col = 0, 8 do
        if empty_masks[col] == nil then
            board.set(b, 0, col, col + 1)
        end
    end
    local cand = candidates.new()
    for col, mask in pairs(empty_masks) do
        cand[1][col + 1] = mask
    end
    return propagator.new(b, masks.new(), cand, flags.HIDDEN_PAIRS)
end

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function pair_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.HIDDEN_PAIRS then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.hidden_pairs", function()
    it("produces hidden pair eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = pair_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata for the pair", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(pair_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("hidden_pair", pattern.kind)
            assert.are.equal(2, #pattern.cells)
            assert.are.equal(2, #pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_true(pattern.values[1] < pattern.values[2])
        end
    end)

    it("eliminates only non-pair candidates from the pair cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(pair_steps(path)) do
            local pattern = step.pattern
            assert.is_true(is_pattern_cell(pattern, step.row, step.col))
            assert.is_false(step.value == pattern.values[1] or step.value == pattern.values[2])
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

    it("finds a hidden pair when one digit occurs once and the other twice", function()
        -- (0,1)={3,5}, (0,4)={1,2,5}, (0,7)={2,3,5}: digit 1 occurs once (at
        -- (0,4)), digit 2 occurs twice (at (0,4) and (0,7)); digits 3 and 5
        -- are spread over the other cells. {1,2} is confined to the two cells
        -- (0,4),(0,7). Standard hidden-pair semantics; the old code required
        -- both digits to occur exactly twice in identical cells and missed
        -- this. (Further sound pairs then cascade to the row's unique
        -- assignment.)
        local p = row0_propagator({
            [1] = bit.bor(bit.lshift(1, 2), bit.lshift(1, 4)),
            [4] = bit.bor(bit.lshift(1, 0), bit.bor(bit.lshift(1, 1), bit.lshift(1, 4))),
            [7] = bit.bor(bit.lshift(1, 1), bit.bor(bit.lshift(1, 2), bit.lshift(1, 4))),
        })
        local path = solve_path.new()

        assert.is_true(hidden_pairs.apply(p, path))

        local found_pair = false
        for _, step in ipairs(path.steps) do
            local pattern = step.pattern
            if
                step.flags == flags.HIDDEN_PAIRS
                and pattern
                and pattern.values[1] == 1
                and pattern.values[2] == 2
                and #pattern.cells == 2
                and pattern.cells[1][1] == 0
                and pattern.cells[1][2] == 4
                and pattern.cells[2][1] == 0
                and pattern.cells[2][2] == 7
            then
                found_pair = true
            end
        end
        assert.is_true(found_pair, "the once-plus-twice pair {1,2} at (0,4),(0,7) must be detected")
        assert.are.equal(bit.lshift(1, 0), p:cand(0, 4), "the row collapses to its unique assignment")
        assert.are.equal(bit.lshift(1, 1), p:cand(0, 7))
        assert.are.equal(bit.lshift(1, 2), p:cand(0, 1))
    end)

    it("does not treat digits scattered across three cells as a pair", function()
        -- (0,1)={1}, (0,4)={1,2}, (0,7)={2}: the union of positions is three
        -- cells, so {1,2} is not confined to two cells and nothing is
        -- eliminated.
        local p = row0_propagator({
            [1] = bit.lshift(1, 0),
            [4] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [7] = bit.lshift(1, 1),
        })
        local path = solve_path.new()

        assert.is_false(hidden_pairs.apply(p, path))
        assert.are.equal(bit.lshift(1, 0), p:cand(0, 1))
        assert.are.equal(bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)), p:cand(0, 4))
        assert.are.equal(bit.lshift(1, 1), p:cand(0, 7))
    end)

    it("does not eliminate when no two-digit union is confined to two cells", function()
        -- (0,1)={1,4}, (0,4)={1,2}, (0,7)={2,4}: every pair of digits spans
        -- all three cells, so no hidden pair exists.
        local p = row0_propagator({
            [1] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 3)),
            [4] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)),
            [7] = bit.bor(bit.lshift(1, 1), bit.lshift(1, 3)),
        })
        local path = solve_path.new()

        assert.is_false(hidden_pairs.apply(p, path))
    end)

    it("does not eliminate when one of the digits never occurs in the unit", function()
        -- (0,1)={1,5}, (0,4)={1,5}, (0,6)={1}: digit 5 occurs exactly twice,
        -- but digit 2 never appears in row 0. A two-cell union alone must not
        -- be treated as a hidden pair: treating the absent 2 as "confined" to
        -- those cells would strip the legitimate candidate 1 from both.
        local p = row0_propagator({
            [1] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 4)),
            [4] = bit.bor(bit.lshift(1, 0), bit.lshift(1, 4)),
            [6] = bit.lshift(1, 0),
        })
        local path = solve_path.new()

        assert.is_false(hidden_pairs.apply(p, path))
        assert.are.equal(bit.bor(bit.lshift(1, 0), bit.lshift(1, 4)), p:cand(0, 1), "candidate 1 must survive")
        assert.are.equal(bit.bor(bit.lshift(1, 0), bit.lshift(1, 4)), p:cand(0, 4), "candidate 1 must survive")
    end)
end)
