package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")

-- HoDoKu hidden quad example: https://hodoku.sourceforge.net/en/show_example.php?file=h401&tech=Hidden+Quad
local HODOKU = "800570290390000000000200000001000508000496000000800000209000001008000070560000082"
local techniques = bit.bor(flags.EASY, flags.HIDDEN_QUADS)

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
        if step.type == "elim" and step.flags == flags.HIDDEN_QUADS then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.hidden_quads", function()
    it("produces hidden quad eliminations", function()
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
            assert.are.equal("hidden_quad", pattern.kind)
            assert.are.equal(4, #pattern.cells)
            assert.are.equal(4, #pattern.values)
            assert.is_not_nil(pattern.unit)
            for i = 1, 3 do
                assert.is_true(pattern.values[i] < pattern.values[i + 1])
            end
        end
    end)

    it("eliminates only non-quad values from the quad cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(quad_steps(path)) do
            local pattern = step.pattern
            assert.is_true(in_unit(pattern.unit, step.row, step.col))
            assert.is_true(is_pattern_cell(pattern, step.row, step.col))
            assert.is_false(is_pattern_value(pattern, step.value))
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
end)
