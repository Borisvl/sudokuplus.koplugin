package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu hidden pair example: https://hodoku.sourceforge.net/en/show_example.php?file=h201&tech=Hidden+Pair
local HODOKU = "000032000000000000007600914096000800005008000030040005050200000700000560904010000"
local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.HIDDEN_PAIRS)

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
end)
