package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")
local prng = require("core.prng")
local solver = require("core.solver")
local sudoku = require("core.sudoku")

local UNIQUE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local UNIQUE_SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local TWO_PUZZLE = "295743861431865900876192543387459216612387495549216738763504189928671354154938600"
local SIX_PUZZLE = "295743001431865900876192543387459216612387495549216738763500000000000000000000000"
local UNSOLVABLE = "078002609030008020002000083000000040043090000007300090200001036001840902050003007"
local DUPLICATES = "530070000600195000098000060800060003400803001700020006060000280000419005500080079"

describe("core.solver", function()
    it("rejects boards with duplicate initial values", function()
        local b = board.from_string(DUPLICATES)
        local s, err = solver.new(b)
        assert.is_nil(s)
        assert.is_string(err)
    end)

    it("solves a unique puzzle to its known solution", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        local solution = s:solve_any()
        assert.is_not_nil(solution)
        assert.are.equal(UNIQUE_SOLUTION, board.to_string(solution.board))
    end)

    it("returns nil for unsolvable puzzles", function()
        local s = solver.new(board.from_string(UNSOLVABLE))
        assert.is_nil(s:solve_any())
    end)

    it("solve_until respects the bound", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        local one = s:solve_until(1)
        local s2 = solver.new(board.from_string(UNIQUE_PUZZLE))
        local all = s2:solve_until(0)
        assert.are.equal(1, #one)
        assert.are.equal(1, #all)
        assert.are.equal(board.to_string(one[1].board), board.to_string(all[1].board))
    end)

    it("counts solutions for unique puzzles", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        assert.are.equal(1, #s:solve_all())
    end)

    it("counts two solutions", function()
        local s = solver.new(board.from_string(TWO_PUZZLE))
        assert.are.equal(2, #s:solve_all())
    end)

    it("counts six solutions", function()
        local s = solver.new(board.from_string(SIX_PUZZLE))
        assert.are.equal(6, #s:solve_all())
    end)

    it("is_solved accepts a valid completed board", function()
        local s = solver.new(board.from_string(UNIQUE_SOLUTION))
        assert.is_true(s:is_solved())
    end)

    it("is_solved rejects incomplete boards", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        assert.is_false(s:is_solved())
    end)

    it("is deterministic with a seeded rng", function()
        local function solve()
            local s = solver.new(board.from_string(TWO_PUZZLE), { rng = prng.new(1234) })
            local sols = s:solve_all()
            return { board.to_string(sols[1].board), board.to_string(sols[2].board) }
        end
        assert.are.same(solve(), solve())
    end)

    it("records placement steps with increasing step numbers", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        local solution = s:solve_any()
        assert.is_not_nil(solution.solve_path)
        assert.is_table(solution.solve_path.steps)
        assert.is_true(#solution.solve_path.steps > 0)
        for i, step in ipairs(solution.solve_path.steps) do
            assert.are.equal("place", step.type)
            assert.are.equal(i - 1, step.step_number)
            assert.is_true(step.value >= 1 and step.value <= 9)
        end
    end)

    it("does not mutate the input board", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        local before = board.to_string(b)
        local s = solver.new(b)
        s:solve_all()
        assert.are.equal(before, board.to_string(b))
    end)
end)

describe("core.sudoku facade", function()
    it("solves via the facade", function()
        local solution = sudoku.solve_any(UNIQUE_PUZZLE)
        assert.are.equal(UNIQUE_SOLUTION, board.to_string(solution.board))
    end)

    it("counts solutions via the facade", function()
        assert.are.equal(1, sudoku.solutions_count(UNIQUE_PUZZLE))
        assert.are.equal(2, sudoku.solutions_count(TWO_PUZZLE))
        assert.are.equal(6, sudoku.solutions_count(SIX_PUZZLE))
    end)

    it("checks solved boards via the facade", function()
        assert.is_true(sudoku.is_solved(UNIQUE_SOLUTION))
        assert.is_false(sudoku.is_solved(UNIQUE_PUZZLE))
    end)
end)
