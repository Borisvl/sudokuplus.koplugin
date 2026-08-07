package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local candidates = require("core.candidates")
local prng = require("core.prng")
local solver = require("core.solver")
local sudoku = require("core.sudoku")
local flags = require("core.techniques.flags")

local UNIQUE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local UNIQUE_SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local TWO_PUZZLE = "295743861431865900876192543387459216612387495549216738763504189928671354154938600"
local SIX_PUZZLE = "295743001431865900876192543387459216612387495549216738763500000000000000000000000"
local UNSOLVABLE = "078002609030008020002000083000000040043090000007300090200001036001840902050003007"
local DUPLICATES = "530070000600195000098000060800060003400803001700020006060000280000419005500080079"
local X_WING_PUZZLE = "000000000760003002002640009403900070000004903005000020010560000370090041000000060"

describe("core.solver", function()
    it("rejects boards with duplicate initial values", function()
        local b = board.from_string(DUPLICATES)
        local s, err = solver.new(b)
        assert.is_nil(s)
        assert.is_string(err)
    end)

    it("rejects malformed board shapes and cell types without throwing", function()
        local nil_solver, nil_err = solver.new(nil)
        assert.is_nil(nil_solver)
        assert.is_string(nil_err)

        local cases = {}

        cases[#cases + 1] = {}

        local sparse = board.new()
        sparse[40] = nil
        cases[#cases + 1] = sparse

        local text_cell = board.new()
        text_cell[1] = "1"
        cases[#cases + 1] = text_cell

        local fractional = board.new()
        fractional[1] = 1.5
        cases[#cases + 1] = fractional

        local extra = board.new()
        extra[82] = 0
        cases[#cases + 1] = extra

        for _, malformed in ipairs(cases) do
            local s, err = solver.new(malformed)
            assert.is_nil(s)
            assert.is_string(err)
        end
    end)

    it("rejects cell values out of range", function()
        local b10 = board.new()
        board.set(b10, 0, 0, 10)
        local s10, err10 = solver.new(b10)
        assert.is_nil(s10)
        assert.is_string(err10)

        local b15 = board.new()
        board.set(b15, 0, 0, 15)
        local s15, err15 = solver.new(b15)
        assert.is_nil(s15)
        assert.is_string(err15)
    end)

    it("accepts a legal candidate cache override", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        local initial = assert(solver.new(b))
        local override = candidates.clone(initial.candidates)
        local before = candidates.get(override, 0, 2)
        local removed = bit.band(before, bit.bnot(bit.lshift(1, 3)))
        candidates.set(override, 0, 2, removed)

        local restored = assert(solver.new(b, { candidates = override }))

        assert.are.equal(removed, candidates.get(restored.candidates, 0, 2))
    end)

    it("rejects illegal candidate cache overrides", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        local initial = assert(solver.new(b))
        local override = candidates.clone(initial.candidates)
        local legal = candidates.get(override, 0, 2)
        local illegal = bit.band(bit.bnot(legal), 0x1FF)
        candidates.set(override, 0, 2, bit.lshift(1, flags.lowest_bit(illegal)))

        local invalid, err = solver.new(b, { candidates = override })

        assert.is_nil(invalid)
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

    it("counts solutions without materializing them and respects a limit", function()
        local s = solver.new(board.from_string(SIX_PUZZLE))
        assert.are.equal(6, s:count_solutions())
        assert.are.equal(2, s:count_solutions(2))
        assert.are.equal(2, #s:solve_all(2))
    end)

    it("rejects invalid solution limits", function()
        local s = solver.new(board.from_string(SIX_PUZZLE))
        local count, count_err = s:count_solutions(-1)
        assert.is_nil(count)
        assert.is_string(count_err)

        local solutions, solve_err = s:solve_all(1.5)
        assert.is_nil(solutions)
        assert.is_string(solve_err)
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

    it("returns only valid solutions that preserve the givens", function()
        local function assert_valid_solutions(puzzle)
            local s = solver.new(board.from_string(puzzle))
            local givens = board.from_string(puzzle)
            for _, solution in ipairs(s:solve_all()) do
                assert.are.equal(81, board.count_clues(solution.board))
                assert.is_not_nil(solver.validate(solution.board))
                for i = 1, 81 do
                    if givens[i] ~= 0 then
                        assert.are.equal(givens[i], solution.board[i])
                    end
                end
            end
        end
        assert_valid_solutions(UNIQUE_PUZZLE)
        assert_valid_solutions(TWO_PUZZLE)
        assert_valid_solutions(SIX_PUZZLE)
    end)

    it("reuses the state after a bounded solve", function()
        local s = solver.new(board.from_string(UNIQUE_PUZZLE))
        local bounded = s:solve_until(1)
        local all = s:solve_until(0)
        assert.are.equal(1, #bounded)
        assert.are.equal(1, #all)
        assert.are.equal(board.to_string(bounded[1].board), board.to_string(all[1].board))
    end)

    it("repeats techniques-enabled solves with complete paths", function()
        local techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.X_WING))
        local s = solver.new(board.from_string(X_WING_PUZZLE), {
            techniques = techniques,
            rng = prng.new(42),
        })
        local first = s:solve_any()
        local second = s:solve_any()

        assert.is_not_nil(first)
        assert.is_not_nil(second)
        assert.is_true(#first.solve_path.steps > 0)
        assert.are.equal(board.to_string(first.board), board.to_string(second.board))
        assert.are.same(first.solve_path.steps, second.solve_path.steps)
        assert.are.equal(X_WING_PUZZLE, board.to_string(s.board))
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

    it("preserves logical eliminations while backtracking", function()
        local s = solver.new(board.new())
        local bit1 = bit.lshift(1, 0)
        candidates.set(s.candidates, 0, 0, bit.bor(bit.lshift(1, 1), bit.lshift(1, 2)))
        candidates.set(s.candidates, 0, 1, bit.band(0x1FF, bit.bnot(bit1)))

        assert.is_not_nil(s:solve_any())
        assert.are.equal(0, bit.band(candidates.get(s.candidates, 0, 1), bit1))
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
        assert.are.equal(2, sudoku.solutions_count(SIX_PUZZLE, nil, 2))
        assert.are.equal(2, #sudoku.solve_all(SIX_PUZZLE, nil, 2))
    end)

    it("checks solved boards via the facade", function()
        assert.is_true(sudoku.is_solved(UNIQUE_SOLUTION))
        assert.is_false(sudoku.is_solved(UNIQUE_PUZZLE))
    end)

    it("preserves facade errors for invalid puzzles", function()
        local solved, solved_err = sudoku.is_solved(DUPLICATES)
        assert.is_false(solved)
        assert.is_string(solved_err)

        local count, count_err = sudoku.solutions_count(DUPLICATES)
        assert.is_nil(count)
        assert.is_string(count_err)
    end)
end)
