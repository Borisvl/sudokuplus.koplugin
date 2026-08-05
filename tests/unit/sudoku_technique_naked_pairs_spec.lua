package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu naked pair example: https://hodoku.sourceforge.net/en/show_example.php?file=n201&tech=Naked+Pair
local HODOKU = "700009030000105006400260009002083951007000000005600000000000003100000060000004010"
local techniques = bit.bor(flags.NAKED_SINGLES, flags.HIDDEN_SINGLES, flags.NAKED_PAIRS)

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

local function pair_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.NAKED_PAIRS then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.naked_pairs", function()
    it("produces naked pair eliminations", function()
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
            assert.are.equal("naked_pair", pattern.kind)
            assert.are.equal(2, #pattern.cells)
            assert.are.equal(2, #pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_true(pattern.unit.type == "row" or pattern.unit.type == "col" or pattern.unit.type == "box")
            assert.is_true(pattern.unit.index >= 0 and pattern.unit.index <= 8)
            assert.is_true(pattern.values[1] < pattern.values[2])
        end
    end)

    it("eliminates only the pair values from other cells of the unit", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(pair_steps(path)) do
            local pattern = step.pattern
            assert.is_true(in_unit(pattern.unit, step.row, step.col))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
            assert.is_true(step.value == pattern.values[1] or step.value == pattern.values[2])
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
