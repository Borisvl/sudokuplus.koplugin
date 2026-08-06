package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

-- HoDoKu skyscraper example: https://hodoku.sourceforge.net/en/show_example.php?file=sk01&tech=Skyscraper
local HODOKU = "000000000001902060000006790902000600370000950005000004140003005709024000000800000"
local techniques = bit.bor(flags.EASY, flags.MEDIUM, flags.SKYSCRAPER)

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function skyscraper_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.SKYSCRAPER then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.skyscraper", function()
    it("produces skyscraper eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = skyscraper_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with base and roof cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(skyscraper_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("skyscraper", pattern.kind)
            assert.are.equal(4, #pattern.cells)
            assert.are.equal(1, #pattern.values)
            assert.are.equal(2, #pattern.base)
            assert.are.equal(2, #pattern.roof)
            -- Base cells share a line; roof cells do not see each other.
            local b1, b2 = pattern.base[1], pattern.base[2]
            assert.is_true(units.sees(b1[1], b1[2], b2[1], b2[2]))
            local r1, r2 = pattern.roof[1], pattern.roof[2]
            assert.is_false(units.sees(r1[1], r1[2], r2[1], r2[2]))
            assert.are.equal(pattern.values[1], step.value)
        end
    end)

    it("eliminates only from cells seeing both roof cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(skyscraper_steps(path)) do
            local pattern = step.pattern
            local r1, r2 = pattern.roof[1], pattern.roof[2]
            assert.is_true(units.sees(step.row, step.col, r1[1], r1[2]))
            assert.is_true(units.sees(step.row, step.col, r2[1], r2[2]))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
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

    it("solves the example guess-free with easy and medium techniques", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        assert.are.equal(81, board.count_clues(s.board))
    end)
end)
