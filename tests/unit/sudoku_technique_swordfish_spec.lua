package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")

-- HoDoKu swordfish example: https://hodoku.sourceforge.net/en/show_example.php?file=bf301&tech=Swordfish
local HODOKU = "160540070008001030030800000700050069600902057000000000000030040000000016000164500"
local techniques = bit.bor(flags.EASY, flags.MEDIUM, flags.SWORDFISH)

local function is_in_lines(lines, r, c)
    for _, unit in ipairs(lines) do
        if unit.type == "row" and r == unit.index then
            return true
        end
        if unit.type == "col" and c == unit.index then
            return true
        end
    end
    return false
end

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function swordfish_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.SWORDFISH then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.swordfish", function()
    it("produces swordfish eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = swordfish_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with base and cover line units", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(swordfish_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("swordfish", pattern.kind)
            assert.are.equal(1, #pattern.values)
            assert.are.equal(3, #pattern.base)
            assert.are.equal(3, #pattern.cover)
            for _, unit in ipairs(pattern.base) do
                assert.is_true(unit.type == "row" or unit.type == "col")
            end
            for _, unit in ipairs(pattern.cover) do
                assert.is_true(unit.type == "row" or unit.type == "col")
            end
            assert.is_true(pattern.base[1].type ~= pattern.cover[1].type)
        end
    end)

    it("eliminates only from cover lines outside the base lines", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(swordfish_steps(path)) do
            local pattern = step.pattern
            assert.is_true(is_in_lines(pattern.cover, step.row, step.col))
            assert.is_false(is_in_lines(pattern.base, step.row, step.col))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
            assert.are.equal(pattern.values[1], step.value)
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
        assert.is_not_nil(solver.validate(s.board))
    end)
end)
