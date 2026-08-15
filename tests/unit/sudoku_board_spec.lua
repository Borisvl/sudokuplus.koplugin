package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local board = require("core.board")

local UNIQUE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local UNIQUE_SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

describe("core.board", function()
    it("parses a valid 81-char string", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        assert.is_not_nil(b)
        assert.are.equal(81, #b)
        assert.are.equal(5, board.get(b, 0, 0))
        assert.are.equal(3, board.get(b, 0, 1))
        assert.are.equal(7, board.get(b, 0, 4))
        assert.are.equal(9, board.get(b, 8, 8))
        assert.are.equal(7, board.get(b, 8, 7))
        assert.are.equal(8, board.get(b, 8, 4))
        assert.are.equal(0, board.get(b, 8, 0))
    end)

    it("rejects input with invalid length", function()
        local b, err = board.from_string("530070000")
        assert.is_nil(b)
        assert.is_string(err)
    end)

    it("rejects non-string input without throwing", function()
        local b, err = board.from_string(nil)
        assert.is_nil(b)
        assert.is_string(err)

        local b2, err2 = board.from_string(123)
        assert.is_nil(b2)
        assert.is_string(err2)
    end)

    it("rejects input with invalid characters", function()
        local b, err =
            board.from_string("53007000060019500009800006080006000340080300170002000606000028000041900500008007X")
        assert.is_nil(b)
        assert.is_string(err)
    end)

    it("treats '.' and '_' as empty cells", function()
        local dotted = (UNIQUE_PUZZLE):gsub("0", ".")
        local underscored = (UNIQUE_PUZZLE):gsub("0", "_")
        local b1 = board.from_string(dotted)
        local b2 = board.from_string(underscored)
        local b3 = board.from_string(UNIQUE_PUZZLE)
        assert.are.same(board.to_string(b1), board.to_string(b3))
        assert.are.same(board.to_string(b2), board.to_string(b3))
    end)

    it("round-trips through to_string", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        assert.are.equal(UNIQUE_PUZZLE, board.to_string(b))
    end)

    it("creates an empty board with 81 zeros", function()
        local b = board.new()
        assert.are.equal(81, #b)
        assert.are.equal(0, board.count_clues(b))
        for r = 0, 8 do
            for c = 0, 8 do
                assert.is_true(board.is_empty(b, r, c))
            end
        end
    end)

    it("get/set/is_empty work with 0-based coordinates", function()
        local b = board.new()
        board.set(b, 8, 8, 9)
        assert.are.equal(9, board.get(b, 8, 8))
        assert.is_false(board.is_empty(b, 8, 8))
        assert.is_true(board.is_empty(b, 0, 0))
        board.set(b, 0, 0, 1)
        assert.are.equal(1, board.get(b, 0, 0))
        assert.are.equal(2, board.count_clues(b))
    end)

    it("rejects coordinates outside the board", function()
        local b = board.new()
        local value, get_err = board.get(b, -1, 0)
        assert.is_nil(value)
        assert.is_string(get_err)

        local set_result, set_err = board.set(b, 9, 0, 1)
        assert.is_nil(set_result)
        assert.is_string(set_err)
        assert.are.equal(0, board.count_clues(b))

        local empty, empty_err = board.is_empty(b, 0, 9)
        assert.is_nil(empty)
        assert.is_string(empty_err)
    end)

    it("clone is independent of the original", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        local copy = board.clone(b)
        assert.are.same(b, copy)
        board.set(copy, 0, 0, 0)
        assert.are.equal(5, board.get(b, 0, 0))
        assert.are.equal(0, board.get(copy, 0, 0))
    end)

    it("counts clues", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        assert.are.equal(30, board.count_clues(b))
        assert.are.equal(0, board.count_clues(board.new()))
    end)

    it("validates that a solution preserves puzzle givens (S7)", function()
        local puzzle = board.from_string(UNIQUE_PUZZLE)
        local solution = board.from_string(UNIQUE_SOLUTION)
        assert.is_true(board.solution_preserves_givens(puzzle, solution))

        -- Mutating a given cell makes it return false
        local corrupted = board.clone(solution)
        board.set(corrupted, 0, 0, 9) -- given was 5
        assert.is_false(board.solution_preserves_givens(puzzle, corrupted))
    end)

    it("raw accessors mirror the validated ones for in-range coordinates", function()
        local b = board.from_string(UNIQUE_PUZZLE)
        board.set(b, 4, 4, 7)
        for r = 0, 8 do
            for c = 0, 8 do
                assert.are.equal(
                    board.get(b, r, c),
                    board.raw_get(b, r, c),
                    string.format("raw_get mismatch at (%d, %d)", r, c)
                )
                assert.are.equal(
                    board.is_empty(b, r, c),
                    board.raw_is_empty(b, r, c),
                    string.format("raw_is_empty mismatch at (%d, %d)", r, c)
                )
            end
        end
    end)

    it("raw_set writes the value at the flat board index", function()
        local b = board.new()
        assert.is_true(board.raw_set(b, 0, 0, 5))
        assert.are.equal(5, b[1])
        assert.are.equal(5, board.raw_get(b, 0, 0))

        assert.is_true(board.raw_set(b, 8, 8, 0))
        assert.are.equal(0, b[81])
        assert.is_true(board.raw_is_empty(b, 8, 8))
    end)

    it("raw accessors do not validate coordinates (hot-path contract)", function()
        local b = board.new()
        assert.is_nil(board.raw_get(b, -1, 0), "raw_get must not error on out-of-range coordinates")
        assert.is_false(board.raw_is_empty(b, -1, 0), "raw_is_empty must not error on out-of-range coordinates")
    end)
end)
