package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local flags = require("core.techniques.flags")
local units = require("core.techniques.units")

-- HoDoKu W-Wing example: https://hodoku.sourceforge.net/en/show_example.php?file=w101&tech=W-Wing
local HODOKU = "025100000000009030400708900040000800150400000000060004000000008263040000080390106"
local techniques = bit.bor(flags.EASY, flags.MEDIUM, flags.W_WING)

local function is_pattern_cell(pattern, r, c)
    for _, cell in ipairs(pattern.cells) do
        if cell[1] == r and cell[2] == c then
            return true
        end
    end
    return false
end

local function w_wing_steps(path)
    local steps = {}
    for _, step in ipairs(path.steps) do
        if step.type == "elim" and step.flags == flags.W_WING then
            steps[#steps + 1] = step
        end
    end
    return steps
end

describe("core.techniques.w_wing", function()
    it("produces w-wing eliminations", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        assert.is_true(s:propagate(path))
        local steps = w_wing_steps(path)
        assert.is_true(#steps > 0)
        for _, step in ipairs(steps) do
            local v_bit = bit.lshift(1, step.value - 1)
            assert.are.equal(0, bit.band(candidates.get(s.candidates, step.row, step.col), v_bit))
        end
    end)

    it("records pattern metadata with pincers and bridge cells", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(w_wing_steps(path)) do
            local pattern = step.pattern
            assert.are.equal("w_wing", pattern.kind)
            assert.are.equal(4, #pattern.cells)
            assert.are.equal(1, #pattern.values)
            assert.are.equal(2, #pattern.pincers)
            assert.are.equal(2, #pattern.bridge)
            assert.is_not_nil(pattern.bridge_value)
            -- The eliminated digit is the non-bridge candidate of the bivalue pair.
            assert.is_true(pattern.values[1] ~= pattern.bridge_value)
            -- Pincers are identical bivalue cells and do not see each other.
            assert.is_false(
                units.sees(pattern.pincers[1][1], pattern.pincers[1][2], pattern.pincers[2][1], pattern.pincers[2][2])
            )
            -- Each pincer sees exactly one end of the bridge link, not the other.
            local p1, p2 = pattern.pincers[1], pattern.pincers[2]
            local b1, b2 = pattern.bridge[1], pattern.bridge[2]
            local link = (units.sees(p1[1], p1[2], b1[1], b1[2]) and units.sees(p2[1], p2[2], b2[1], b2[2]))
                or (units.sees(p1[1], p1[2], b2[1], b2[2]) and units.sees(p2[1], p2[2], b1[1], b1[2]))
            assert.is_true(link)
            assert.are.equal(pattern.values[1], step.value)
        end
    end)

    it("eliminates only from cells seeing both pincers", function()
        local s = solver.new(board.from_string(HODOKU), { techniques = techniques })
        local path = solve_path.new()
        s:propagate(path)
        for _, step in ipairs(w_wing_steps(path)) do
            local pattern = step.pattern
            local p1, p2 = pattern.pincers[1], pattern.pincers[2]
            assert.is_true(units.sees(step.row, step.col, p1[1], p1[2]))
            assert.is_true(units.sees(step.row, step.col, p2[1], p2[2]))
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
