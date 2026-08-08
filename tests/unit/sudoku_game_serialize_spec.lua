package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local game = require("game")

local PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
local NAKED_SINGLE_SOLUTION = "385421967194756328627983145571892634839645271246137589462579813918364752753218496"

local function digit_bit(v)
    return bit.lshift(1, v - 1)
end

local function has_note(instance, r, c, v)
    return bit.band(instance:get_notes(r, c), digit_bit(v)) ~= 0
end

local function new_game(puzzle, solution)
    local clock = { t = 1000 }
    local instance = assert(game.new({
        puzzle = board.from_string(puzzle or PUZZLE),
        solution = board.from_string(solution or SOLUTION),
        difficulty = "hard",
        now = function()
            return clock.t
        end,
    }))
    return instance, clock
end

local function play_some_moves(instance)
    assert.is_true(instance:place(0, 2, 2))
    assert.is_true(instance:toggle_note(0, 3, 6))
    assert.is_true(instance:place(0, 2, 4))
    assert.is_true(instance:erase(0, 2))
    assert.is_true(instance:undo())
end

local function restore(data, clock)
    return assert(game.restore(data, {
        now = function()
            return clock.t
        end,
    }))
end

describe("game serialization", function()
    it("round-trips the full state including history", function()
        local instance = new_game()
        play_some_moves(instance)
        assert.is_true(instance:clear_notes(0, 5))
        instance:check_for_errors()

        local data = instance:serialize()
        local restored = restore(data, { t = 1000 })

        assert.are.equal(board.to_string(instance.board), board.to_string(restored.board))
        assert.are.equal(instance:difficulty(), restored:difficulty())
        assert.are.equal(instance:revision(), restored:revision())
        assert.are.equal(instance:mistakes(), restored:mistakes())
        assert.are.equal(instance:check_errors(), restored:check_errors())
        assert.are.equal(instance:elapsed(), restored:elapsed())
        for r = 0, 8 do
            for c = 0, 8 do
                assert.are.equal(instance:get_notes(r, c), restored:get_notes(r, c))
            end
        end
        assert.is_false(restored:is_finished())
    end)

    it("preserves difficulty when restoring and reserializing", function()
        local instance = new_game()
        local restored = restore(instance:serialize(), { t = 1000 })

        assert.are.equal("hard", restored:difficulty())
        assert.are.equal("hard", restored:serialize().difficulty)
    end)

    it("restores a playable history: undo and redo still work", function()
        local instance = new_game()
        assert.is_true(instance:place(0, 2, 2))
        assert.is_true(instance:toggle_note(0, 3, 6))

        local restored = restore(instance:serialize(), { t = 1000 })
        assert.is_true(restored:can_undo())
        assert.is_true(restored:can_redo())

        assert.is_true(restored:undo())
        assert.is_false(has_note(restored, 0, 3, 6))
        assert.is_true(restored:undo())
        assert.are.equal(0, restored:get(0, 2))
        assert.is_true(restored:redo())
        assert.are.equal(2, restored:get(0, 2))

        assert.is_true(restored:place(0, 3, 4))
        assert.is_false(restored:can_redo())
    end)

    it("preserves a running timer across restore", function()
        local instance, clock = new_game()
        clock.t = 1015
        assert.are.equal(15, instance:elapsed())

        local data = instance:serialize()
        clock.t = 1016
        local restored = restore(data, clock)
        assert.are.equal(16, restored:elapsed())
        clock.t = 1030
        assert.are.equal(30, restored:elapsed(), "timer keeps running after restore")
    end)

    it("preserves a paused timer across restore", function()
        local instance, clock = new_game()
        clock.t = 1015
        assert.is_true(instance:pause())

        local restored = restore(instance:serialize(), clock)
        assert.are.equal(15, restored:elapsed())
        clock.t = 1030
        assert.are.equal(15, restored:elapsed(), "timer stays paused after restore")
        assert.is_true(restored:resume())
        clock.t = 1040
        assert.are.equal(25, restored:elapsed())
    end)

    it("restores hint records and the finished flag", function()
        local instance = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)
        local result = assert(instance:hint())
        assert.is_true(instance:apply_action(result.action))
        assert.is_not_nil(instance:finish())

        local data = instance:serialize()
        assert.is_true(data.finished)
        assert.are.equal(1, #data.hints)

        local restored = restore(data, { t = 1000 })
        assert.is_true(restored:is_finished())
        assert.are.equal(1, #restored:hints())
        assert.are.equal("naked_singles", restored:hints()[1].technique)
        local move_ok, move_err = restored:place(0, 2, 4)
        assert.is_nil(move_ok)
        assert.is_string(move_err)
    end)

    it("restores conflicting and error states consistently", function()
        local instance = new_game()
        assert.is_true(instance:place(0, 7, 5))
        assert.is_true(instance:place(0, 2, 2))
        instance:check_for_errors()

        local restored = restore(instance:serialize(), { t = 1000 })
        assert.are.equal(2, #restored:conflicts())
        assert.are.equal(1, restored:mistakes())
        assert.are.equal(1, restored:check_errors())
        assert.are.equal(1, #restored:revealed())
        assert.are.same({ 0, 2 }, restored:revealed()[1])
    end)

    it("does not share mutable state with the source instance", function()
        local instance = new_game()
        play_some_moves(instance)
        local notes_before = instance:get_notes(1, 1)
        local data = instance:serialize()
        local restored = restore(data, { t = 1000 })

        assert.is_true(restored:place(1, 1, 2))
        assert.are.equal(0, instance:get(1, 1), "source board untouched")
        assert.are.equal(notes_before, instance:get_notes(1, 1), "source notes untouched")
        assert.are.equal(0, restored:get_notes(1, 1))
    end)

    it("rejects malformed save data", function()
        local now = function()
            return 0
        end
        local instance = new_game()
        local cases = {
            { name = "not a table", data = "garbage" },
            { name = "bad version", data = { version = 99 } },
            { name = "short board", data = { version = 1, board = "12" } },
        }
        for _, case in ipairs(cases) do
            local restored, err = game.restore(case.data, { now = now })
            assert.is_nil(restored, case.name .. " must be rejected")
            assert.is_string(err, case.name .. " must report an error")
        end

        local broken_givens = instance:serialize()
        broken_givens.board = board.to_string(instance.board):sub(1, 80) .. "9"
        local restored, err = game.restore(broken_givens, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        local bad_timer = instance:serialize()
        bad_timer.timer = { running = true, elapsed = -1 }
        restored, err = game.restore(bad_timer, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        local bad_finished = instance:serialize()
        bad_finished.finished = "yes"
        restored, err = game.restore(bad_finished, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        local bad_history = instance:serialize()
        bad_history.history = { { kind = "teleport" } }
        restored, err = game.restore(bad_history, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        local bad_undo_ptr = instance:serialize()
        bad_undo_ptr.undo_ptr = 99
        restored, err = game.restore(bad_undo_ptr, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("rejects illegal notes and filled cells with notes", function()
        local instance = new_game()

        local illegal_notes = instance:serialize()
        illegal_notes.notes[1][3] = illegal_notes.notes[1][3] + 512
        local restored, err = game.restore(illegal_notes, {
            now = function()
                return 0
            end,
        })
        assert.is_nil(restored)
        assert.is_string(err)

        local notes_on_given = instance:serialize()
        notes_on_given.notes[1][1] = 4
        restored, err = game.restore(notes_on_given, {
            now = function()
                return 0
            end,
        })
        assert.is_nil(restored)
        assert.is_string(err)
    end)
end)
