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

    it("records the generation seed when one is provided", function()
        local payload, err = generator.generate_game({
            difficulty = "easy",
            seed = 1234567,
            rng = prng.new(1234567),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.are.equal(1234567, payload.seed, "the payload must expose the seed for reproduction")
    end)

    it("snapshots the rng state as the seed when none is provided", function()
        -- A fresh prng.new(seed) stores the normalized seed in state; recording
        -- it lets the puzzle be reproduced with prng.new(payload.seed).
        local payload, err = generator.generate_game({ difficulty = "easy", rng = prng.new(4242) })

        assert.is_nil(err)
        assert.is_not_nil(payload)
        assert.are.equal(prng.new(4242).state, payload.seed, "seed must be the rng's initial state")

        local replay, replay_err = generator.generate_game({
            difficulty = "easy",
            rng = prng.new(payload.seed),
        })
        assert.is_nil(replay_err)
        assert.is_not_nil(replay)
        assert.are.equal(
            board.to_string(payload.board),
            board.to_string(replay.board),
            "the recorded seed must reproduce the exact puzzle"
        )
    end)

    it("rejects a non-integer seed", function()
        local payload, err = generator.generate_game({
            difficulty = "easy",
            seed = 1.5,
            rng = prng.new(4242),
        })

        assert.is_nil(payload)
        assert.is_string(err)
    end)

    it("never hard-fails on an exact difficulty match: returns the closest valid puzzle", function()
        -- Force every attempt to classify as "hard" so "medium" can never
        -- match exactly; the generator must fall back to the closest usable
        -- puzzle (labeled with its actual difficulty) instead of failing.
        local solve_path_mod = require("core.solve_path")
        local original_classify = solve_path_mod.classify
        solve_path_mod.classify = function()
            return {
                difficulty = "hard",
                requires_guessing = false,
                hardest_flags = flags.X_WING,
                hardest_step_number = 1,
            }
        end
        finally(function()
            solve_path_mod.classify = original_classify
        end)

        local payload, err = generator.generate_game({
            difficulty = "medium",
            max_attempts = 20,
            rng = prng.new(9999),
        })

        assert.is_nil(err)
        assert.is_not_nil(payload, "a best-effort puzzle must be returned instead of failing")
        assert.are.equal("hard", payload.difficulty, "the payload reports the actual classification")
        assert.are.equal(board.count_clues(payload.board), payload.clues)
        assert.is_not_nil(payload.solution)
    end)
end)
