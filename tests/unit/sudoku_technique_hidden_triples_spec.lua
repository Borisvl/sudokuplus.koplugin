package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu hidden triple example: https://hodoku.sourceforge.net/en/show_example.php?file=h301&tech=Hidden+Triple
local HODOKU = "200000400500000006001034080000500040000000000060790000090200600003009001000080037"
local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.HIDDEN_TRIPLES)

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
        if step.type == "elim" and step.flags == flags.HIDDEN_TRIPLES then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.hidden_triples", function()
    it("produces hidden triple eliminations", function()
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
            assert.are.equal("hidden_triple", pattern.kind)
            assert.are.equal(3, #pattern.cells)
            assert.are.equal(3, #pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_true(pattern.values[1] < pattern.values[2] and pattern.values[2] < pattern.values[3])
        end
    end)

    it("eliminates only non-triple candidates from the triple cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(triple_steps(path)) do
            local pattern = step.pattern
            assert.is_true(is_pattern_cell(pattern, step.row, step.col))
            local in_values = step.value == pattern.values[1]
                or step.value == pattern.values[2]
                or step.value == pattern.values[3]
            assert.is_false(in_values)
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
