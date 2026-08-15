package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")

-- HoDoKu locked candidates (pointing) example:
-- https://hodoku.sourceforge.net/en/show_example.php?file=lc101&tech=Locked+Candidates+Type+1+%28Pointing%29
local HODOKU = "984000000000500040000000002006097200003002000000000010005060003407051890030009700"

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

local function locked_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.LOCKED_CANDIDATES then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.locked_candidates", function()
    it("produces locked candidate eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.LOCKED_CANDIDATES })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = locked_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with unit and target", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.LOCKED_CANDIDATES })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(locked_steps(path)) do
            local pattern = step.pattern
            assert.is_true(pattern.kind == "pointing" or pattern.kind == "claiming")
            assert.is_true(#pattern.cells >= 1)
            assert.are.equal(1, #pattern.values)
            assert.is_not_nil(pattern.unit)
            assert.is_not_nil(pattern.target)
            if pattern.kind == "pointing" then
                assert.is_true(pattern.unit.type == "row" or pattern.unit.type == "col")
                assert.are.equal("box", pattern.target.type)
            else
                assert.are.equal("box", pattern.unit.type)
                assert.is_true(pattern.target.type == "row" or pattern.target.type == "col")
            end
        end
    end)

    it("eliminates from the target unit outside the pattern unit", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.LOCKED_CANDIDATES })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(locked_steps(path)) do
            local pattern = step.pattern
            assert.is_true(in_unit(pattern.target, step.row, step.col))
            assert.is_false(in_unit(pattern.unit, step.row, step.col))
            assert.is_false(is_pattern_cell(pattern, step.row, step.col))
        end
    end)

    it("does not alter the givens", function()
        local original = board.from_string(HODOKU)
        local s = solver.new(board.from_string(HODOKU), { techniques = flags.LOCKED_CANDIDATES })
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
