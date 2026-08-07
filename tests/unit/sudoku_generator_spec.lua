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

local SYMMETRIES = {
    "none",
    "rotational180",
    "rotational90",
    "mirrorvertical",
    "mirrorhorizontal",
    "mirrordiagonal",
}

local function cell_index(row, col)
    return row * 9 + col + 1
end

local function partners(symmetry, row, col)
    local cells = {}
    local seen = {}

    local function add(partner_row, partner_col)
        local index = cell_index(partner_row, partner_col)
        if not seen[index] then
            seen[index] = true
            cells[#cells + 1] = { partner_row, partner_col }
        end
    end

    add(row, col)
    if symmetry == "rotational180" then
        add(8 - row, 8 - col)
    elseif symmetry == "rotational90" then
        add(col, 8 - row)
        add(8 - row, 8 - col)
        add(8 - col, row)
    elseif symmetry == "mirrorvertical" then
        add(row, 8 - col)
    elseif symmetry == "mirrorhorizontal" then
        add(8 - row, col)
    elseif symmetry == "mirrordiagonal" then
        add(col, row)
    end

    return cells
end

local function assert_symmetric(puzzle, symmetry)
    for row = 0, 8 do
        for col = 0, 8 do
            local empty = board.is_empty(puzzle, row, col)
            for _, partner in ipairs(partners(symmetry, row, col)) do
                assert.are.equal(empty, board.is_empty(puzzle, partner[1], partner[2]))
            end
        end
    end
end

describe("core.generator", function()
    it("rejects invalid generation options", function()
        local puzzle, clues_err = generator.generate({ clues = 16 })
        assert.is_nil(puzzle)
        assert.is_string(clues_err)

        local bad_symmetry, symmetry_err = generator.generate({ symmetry = "diagonal" })
        assert.is_nil(bad_symmetry)
        assert.is_string(symmetry_err)

        local bad_difficulty, difficulty_err = generator.generate({ difficulty = "trivial" })
        assert.is_nil(bad_difficulty)
        assert.is_string(difficulty_err)

        local bad_attempts, attempts_err = generator.generate({ difficulty = "easy", max_attempts = 0 })
        assert.is_nil(bad_attempts)
        assert.is_string(attempts_err)
    end)

    it("generates a deterministic uniquely solvable puzzle", function()
        local options = { clues = 30, rng = prng.new(12345) }
        local first = generator.generate(options)
        local second = generator.generate({ clues = 30, rng = prng.new(12345) })

        assert.is_not_nil(first)
        assert.is_not_nil(second)
        assert.are.equal(board.to_string(first), board.to_string(second))
        assert.is_true(board.count_clues(first) >= 30)

        local solver_instance = solver.new(first)
        local solutions = solver_instance:solve_until(2)
        assert.are.equal(1, #solutions)
        assert.is_false(solver_instance:is_solved())
        assert.is_not_nil(solver.validate(solutions[1].board))

        for i = 1, 81 do
            if first[i] ~= 0 then
                assert.are.equal(first[i], solutions[1].board[i])
            end
        end
    end)

    it("preserves clue symmetry for every supported mode", function()
        for i, symmetry in ipairs(SYMMETRIES) do
            local puzzle, err = generator.generate({
                clues = 72,
                symmetry = symmetry,
                rng = prng.new(700 + i),
            })

            assert.is_nil(err)
            assert.is_not_nil(puzzle)
            assert.is_true(board.count_clues(puzzle) >= 72)
            assert_symmetric(puzzle, symmetry)
        end
    end)

    it("targets exact human-solve difficulty without guessing", function()
        local targets = {
            { name = "easy", seed = 101 },
            { name = "medium", seed = 102 },
            { name = "hard", seed = 103 },
            { name = "expert", seed = 104 },
        }

        for _, target in ipairs(targets) do
            local puzzle, err = generator.generate({
                difficulty = target.name,
                max_attempts = 100,
                rng = prng.new(target.seed),
            })
            assert.is_nil(err)
            assert.is_not_nil(puzzle)

            local human_solver = solver.new(puzzle, {
                techniques = ALL_TECHNIQUES,
                rng = prng.new(target.seed),
            })
            local solutions = human_solver:solve_until(2)
            assert.are.equal(1, #solutions)

            local classification = solve_path.classify(solutions[1].solve_path)
            assert.are.equal(target.name, classification.difficulty)
            assert.is_false(classification.requires_guessing)
        end
    end)

    it("is available through the sudoku facade", function()
        local puzzle, err = sudoku.generate({ clues = 81, rng = prng.new(9) })

        assert.is_nil(err)
        assert.is_not_nil(puzzle)
        assert.are.equal(81, board.count_clues(puzzle))
        assert.is_not_nil(solver.validate(puzzle))
    end)
end)
