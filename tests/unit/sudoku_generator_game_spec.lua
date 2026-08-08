package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local generator = require("core.generator")
local prng = require("core.prng")
local solve_path = require("core.solve_path")
local solver = require("core.solver")
local sudoku = require("core.sudoku")
local flags = require("core.techniques.flags")

local ALL_TECHNIQUES = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.EXPERT)))

describe("core.generator game payload", function()
    it("returns puzzle, solution, difficulty and clue count", function()
        local payload, err = generator.generate_game({
            difficulty = "medium",
            max_attempts = 50,
            rng = prng.new(4242),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.board)
        assert.is_not_nil(payload.solution)
        assert.are.equal("medium", payload.difficulty)
        assert.are.equal(board.count_clues(payload.board), payload.clues)

        assert.are.equal(81, board.count_clues(payload.solution))
        assert.is_not_nil(solver.validate(payload.solution))
        for i = 1, 81 do
            if payload.board[i] ~= 0 then
                assert.are.equal(payload.board[i], payload.solution[i])
            end
        end

        local solutions = solver.new(payload.board):solve_until(2)
        assert.are.equal(1, #solutions)
        assert.are.equal(board.to_string(payload.solution), board.to_string(solutions[1].board))
    end)

    it("classifies difficulty when none is requested", function()
        local payload, err = generator.generate_game({ rng = prng.new(77) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.difficulty)
        assert.is_not_nil(payload.solution)
        assert.are.equal(board.count_clues(payload.board), payload.clues)
    end)

    it("does not label a guessing puzzle as a technique-only game", function()
        local payload, err = generator.generate_game({ rng = prng.new(85) })
        assert.is_nil(err)
        assert.is_not_nil(payload)

        local solutions = solver
            .new(payload.board, {
                techniques = ALL_TECHNIQUES,
                rng = prng.new(85),
            })
            :solve_until(2)
        assert.are.equal(1, #solutions)
        local classification = solve_path.classify(solutions[1].solve_path)

        assert.is_false(classification.requires_guessing)
    end)

    it("rejects invalid options like generate", function()
        local payload, err = generator.generate_game({ difficulty = "impossible", rng = prng.new(1) })

        assert.is_nil(payload)
        assert.is_string(err)
    end)

    it("is deterministic for a fixed seed", function()
        local a, a_err = generator.generate_game({ difficulty = "easy", rng = prng.new(123) })
        local b, b_err = generator.generate_game({ difficulty = "easy", rng = prng.new(123) })

        assert.is_nil(a_err)
        assert.is_nil(b_err)
        assert.are.equal(board.to_string(a.board), board.to_string(b.board))
        assert.are.equal(board.to_string(a.solution), board.to_string(b.solution))
        assert.are.equal(a.difficulty, b.difficulty)
    end)

    it("is exposed through the sudoku facade", function()
        local payload, err = sudoku.generate_game({ difficulty = "hard", rng = prng.new(5) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.is_not_nil(payload.solution)
        assert.are.equal("hard", payload.difficulty)
    end)
end)
