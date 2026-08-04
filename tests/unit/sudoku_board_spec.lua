package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")

local UNIQUE_PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"

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

    it("iterates empty cells", function()
        local b = board.new()
        board.set(b, 0, 0, 1)
        local cells = board.iter_empty_cells(b)
        assert.are.equal(80, #cells)
        assert.are.same({ 0, 1 }, cells[1])
        assert.are.same({ 8, 8 }, cells[#cells])
    end)
end)
