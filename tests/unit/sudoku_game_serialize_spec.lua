package.path = "plugins/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("core.board")
local game = require("game")
local game_serialize = require("game_serialize")
local json = require("json")
local util = require("core.util")

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

    it("round-trips a game save through the JSON codec", function()
        local instance = new_game()
        play_some_moves(instance)

        local encoded, encode_err = json.encode(instance:serialize())
        assert.is_nil(encode_err)
        local decoded, decode_err = json.decode(encoded)
        assert.is_nil(decode_err)

        local restored = restore(decoded, { t = 1000 })
        assert.are.equal(board.to_string(instance.board), board.to_string(restored.board))
        assert.are.equal(instance:revision(), restored:revision())
        assert.are.equal(instance:get_notes(0, 3), restored:get_notes(0, 3))
    end)

    it("restores a playable history: undo and redo still work", function()
        local instance = new_game()
        assert.is_true(instance:toggle_note(0, 3, 2))
        assert.is_true(instance:place(0, 2, 2))
        assert.is_false(has_note(instance, 0, 3, 2), "placed digit auto-cleaned")
        assert.is_true(instance:toggle_note(0, 3, 6))
        assert.is_true(instance:undo())

        local restored = restore(instance:serialize(), { t = 1000 })
        assert.is_true(restored:can_undo())
        assert.is_true(restored:can_redo())

        assert.is_true(restored:undo())
        assert.is_false(has_note(restored, 0, 3, 6), "note toggle stays undone")
        assert.are.equal(0, restored:get(0, 2))
        assert.is_true(has_note(restored, 0, 3, 2), "auto-cleaned note restored")
        assert.is_true(restored:redo())
        assert.are.equal(2, restored:get(0, 2))
        assert.is_false(has_note(restored, 0, 3, 2))
        assert.is_true(restored:redo())
        assert.is_true(has_note(restored, 0, 3, 6))

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

        -- An in-progress restored game deduplicates already seen hints
        local in_progress_inst = new_game(NAKED_SINGLE_PUZZLE, NAKED_SINGLE_SOLUTION)
        local hint_res = assert(in_progress_inst:hint())
        local in_progress_data = in_progress_inst:serialize()
        local in_progress_restored = restore(in_progress_data, { t = 1000 })
        assert.are.equal(1, #in_progress_restored:hints())
        local re_hint = assert(in_progress_restored:hint())
        assert.are.equal(hint_res.hint_id, re_hint.hint_id)
        assert.are.equal(1, #in_progress_restored:hints(), "restored game must not duplicate already seen hint")

        local move_ok, move_err = restored:place(0, 2, 4)
        assert.is_nil(move_ok)
        assert.is_string(move_err)
    end)

    it("restores batch notes elimination history and supports undo/redo", function()
        local instance = new_game()
        assert.is_true(instance:toggle_note(0, 2, 1))
        assert.is_true(instance:toggle_note(0, 2, 4))
        -- Cell (0, 3) has empty notes (Option 1)
        assert.is_true(instance:apply_action({
            type = "batch",
            actions = {
                { type = "elim", row = 0, col = 2, value = 1 },
                { type = "elim", row = 0, col = 2, value = 4 },
                { type = "elim", row = 0, col = 3, value = 2 },
            },
        }))

        local restored = restore(instance:serialize(), { t = 1000 })
        assert.is_false(has_note(restored, 0, 2, 1))
        assert.is_false(has_note(restored, 0, 2, 4))
        assert.is_false(has_note(restored, 0, 3, 2))
        assert.is_true(restored:get_notes(0, 3) > 0)
        assert.are.equal(bit.bor(digit_bit(1), digit_bit(4)), restored.manual_removed[1][3])
        assert.are.equal(digit_bit(2), restored.manual_removed[1][4])

        assert.is_true(restored:undo())
        assert.is_true(has_note(restored, 0, 2, 1))
        assert.is_true(has_note(restored, 0, 2, 4))
        assert.are.equal(0, restored:get_notes(0, 3))
        assert.are.equal(0, restored.manual_removed[1][3])
        assert.are.equal(0, restored.manual_removed[1][4])

        assert.is_true(restored:redo())
        assert.is_false(has_note(restored, 0, 2, 1))
        assert.is_false(has_note(restored, 0, 2, 4))
        assert.is_false(has_note(restored, 0, 3, 2))
        assert.is_true(restored:get_notes(0, 3) > 0)
        assert.are.equal(bit.bor(digit_bit(1), digit_bit(4)), restored.manual_removed[1][3])
        assert.are.equal(digit_bit(2), restored.manual_removed[1][4])
    end)

    it("restores conflicting and error states consistently", function()
        local instance = new_game()
        assert.is_true(instance:place(0, 7, 5))
        assert.is_true(instance:place(0, 2, 2))
        instance:check_for_errors()

        local restored = restore(instance:serialize(), { t = 1000 })
        assert.are.equal(2, #restored:conflicts())
        assert.are.equal(1, restored:mistakes())
        assert.are.equal(2, restored:check_errors())
        local revealed = restored:revealed()
        assert.are.equal(2, #revealed)
        local found = {}
        for _, cell in ipairs(revealed) do
            found[cell[1] * 9 + cell[2]] = true
        end
        assert.is_true(found[0 * 9 + 2])
        assert.is_true(found[0 * 9 + 7])
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

    it("does not expose mutable history through serialized state", function()
        local instance = new_game()
        assert.is_true(instance:place(0, 2, 2))

        local data = instance:serialize()
        data.history[1].old = 9

        assert.is_true(instance:undo())
        assert.are.equal(0, instance:get(0, 2))
    end)

    it("round-trips a reproduction seed through save and restore", function()
        local clock = { t = 1000 }
        local seeded = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "easy",
            seed = 424242,
            techniques = { "locked_candidates", "naked_pairs" },
            now = function()
                return clock.t
            end,
        }))

        local data = seeded:serialize()
        assert.are.equal(424242, data.seed, "the save must carry the reproduction seed")
        assert.are.same({ "locked_candidates", "naked_pairs" }, data.techniques)

        local restored = restore(data, { t = 1000 })
        assert.are.equal(424242, restored.seed, "restore must keep the reproduction seed")
        assert.are.same({ "locked_candidates", "naked_pairs" }, restored:techniques())
    end)

    it("rejects invalid techniques in save data", function()
        local instance = new_game()
        local data = instance:serialize()
        data.techniques = "naked_pairs"
        local now = function()
            return 0
        end
        local restored, err = game.restore(data, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        data.techniques = { 123 }
        restored, err = game.restore(data, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        data.techniques = { "" }
        restored, err = game.restore(data, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("restores save data with forward-compatible technique string ids", function()
        local instance = new_game()
        local data = instance:serialize()
        data.techniques = { "future_killer_technique" }
        local restored, err = game.restore(data, {
            now = function()
                return 0
            end,
        })
        assert.is_nil(err)
        assert.is_not_nil(restored)
        assert.are.same({ "future_killer_technique" }, restored:techniques())
    end)

    it("rejects a non-integer seed in save data", function()
        local instance = new_game()
        local data = instance:serialize()
        data.seed = 1.5
        local now = function()
            return 0
        end
        local restored, err = game.restore(data, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("round-trips the game id through save and restore", function()
        local clock = { t = 1000 }
        local with_id = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "easy",
            id = 77,
            now = function()
                return clock.t
            end,
        }))
        local data = with_id:serialize()
        assert.are.equal(77, data.id, "the save must carry the game id")

        local restored = restore(data, { t = 1000 })
        assert.are.equal(77, restored.id, "restore must keep the game id")
    end)

    it("restores saves without a game id as nil", function()
        local instance = new_game()
        local data = instance:serialize()
        assert.is_nil(data.id)
        local restored = restore(data, { t = 1000 })
        assert.is_nil(restored.id, "older saves keep a nil game id")
    end)

    it("rejects a non-integer game id in save data", function()
        local instance = new_game()
        local data = instance:serialize()
        data.id = 1.5
        local restored, err = game.restore(data, {
            now = function()
                return 0
            end,
        })
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("preserves the started timestamp in save data", function()
        local clock = { t = 1000 }
        local instance = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "easy",
            now = function()
                return clock.t
            end,
        }))
        assert.is_true(instance:place(0, 2, 2))
        local data = instance:serialize()
        assert.are.equal(1000, data.started_at)

        local never = game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "easy",
            now = function()
                return clock.t
            end,
        })
        assert.is_nil(never:serialize().started_at, "an unstarted game has no started timestamp")
    end)

    it("rejects a malformed started timestamp", function()
        local instance = new_game()
        local data = instance:serialize()
        data.started_at = math.huge
        local restored, err = game.restore(data, {
            now = function()
                return 0
            end,
        })
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("restores saves written before the seed field existed", function()
        local instance = new_game()
        local data = instance:serialize()
        data.seed = nil
        local restored = restore(data, { t = 1000 })
        assert.is_nil(restored.seed, "a missing seed must stay nil for older saves")
    end)

    it("rejects malformed save data", function()
        local now = function()
            return 0
        end
        local instance = new_game()
        local cases = {
            { name = "not a table", data = "garbage" },
            { name = "bad version", data = { version = 99 } },
            { name = "legacy v1 version", data = { version = 1 } },
            { name = "short board", data = { version = 3, board = "12" } },
        }
        for _, case in ipairs(cases) do
            local restored, err = game.restore(case.data, { now = now })
            assert.is_nil(restored, case.name .. " must be rejected")
            assert.is_string(err, case.name .. " must report an error")
        end

        local broken_givens = instance:serialize()
        broken_givens.board = board.to_string(instance.board):sub(1, 80) .. "8"
        local restored, err = game.restore(broken_givens, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        local bad_timer = instance:serialize()
        bad_timer.timer = { running = true, elapsed = -1 }
        restored, err = game.restore(bad_timer, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        bad_timer = instance:serialize()
        bad_timer.timer = { running = true, elapsed = math.huge }
        restored, err = game.restore(bad_timer, { now = now })
        assert.is_nil(restored)
        assert.is_string(err)

        bad_timer = instance:serialize()
        bad_timer.timer = { running = true, elapsed = 5 }
        restored, err = game.restore(bad_timer, { now = now })
        assert.is_nil(restored)
        assert.is_string(err, "a running timer without a start time must be rejected")

        local bad_started_past = instance:serialize()
        bad_started_past.timer = { running = true, elapsed = 5, started = -1e12 }
        restored, err = game.restore(bad_started_past, { now = now })
        assert.is_nil(restored)
        assert.is_string(err, "a running timer with an out-of-window start time must be rejected")

        local bad_started_future = instance:serialize()
        bad_started_future.timer = { running = true, elapsed = 5, started = 1e12 }
        restored, err = game.restore(bad_started_future, { now = now })
        assert.is_nil(restored)
        assert.is_string(err, "a running timer with a future start time must be rejected")

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

    it("rejects malformed history fields without throwing", function()
        local instance = new_game()
        local now = function()
            return 0
        end

        local bad_type = instance:serialize()
        bad_type.history = { { kind = "place", r = 0, c = 2, value = 4, old = "bad" } }
        local ok, restored, err = pcall(game.restore, bad_type, { now = now })
        assert.is_true(ok)
        assert.is_nil(restored)
        assert.is_string(err)

        local missing_old = instance:serialize()
        missing_old.history = { { kind = "place", r = 0, c = 2, value = 4 } }
        ok, restored, err = pcall(game.restore, missing_old, { now = now })
        assert.is_true(ok)
        assert.is_nil(restored)
        assert.is_string(err)
    end)

    it("round-trips history containing fill_all_notes", function()
        local instance = new_game()
        assert.is_true(instance:place(0, 2, 4))
        assert.is_true(instance:fill_all_notes())
        assert.is_true(instance:place(0, 3, 6))

        local data = instance:serialize()
        local restored = restore(data, { t = 1000 })

        assert.is_true(restored:can_undo())
        assert.is_true(restored:undo()) -- undo place(0,3,6)
        assert.is_true(restored:undo()) -- undo fill_all_notes
        assert.are.equal(0, restored:get_notes(0, 5))
        assert.is_true(restored:redo()) -- redo fill_all_notes
        assert.is_true(restored:get_notes(0, 5) > 0)
    end)

    it("exports serialize and restore directly from game_serialize module", function()
        local instance = new_game()
        assert.are.equal(3, game_serialize.VERSION)
        local serialized = game_serialize.serialize(instance)
        assert.are.equal(3, serialized.version)

        local raw_restored, err = game_serialize.restore(serialized, {
            now = function()
                return 1000
            end,
        })
        assert.is_nil(err)
        assert.is_not_nil(raw_restored)
        assert.are.equal("hard", raw_restored._difficulty)
    end)

    it("restores legacy version 2 saves seamlessly", function()
        local instance = new_game()
        local serialized = game_serialize.serialize(instance)
        serialized.version = 2

        local restored, err = game_serialize.restore(serialized, {
            now = function()
                return 1000
            end,
        })
        assert.is_nil(err)
        assert.is_not_nil(restored)
        assert.are.equal("hard", restored._difficulty)
    end)

    it("round-trips custom difficulty fields (custom_tier, custom_techniques, allowed_techniques)", function()
        local clock = { t = 1000 }
        local instance = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "custom",
            custom_tier = "master",
            custom_techniques = { "swordfish", "x_wing" },
            allowed_techniques = 0x1234,
            now = function()
                return clock.t
            end,
        }))

        local serialized = instance:serialize()
        assert.are.equal("custom", serialized.difficulty)
        assert.are.equal("master", serialized.custom_tier)
        assert.are.same({ "swordfish", "x_wing" }, serialized.custom_techniques)
        assert.are.equal(0x1234, serialized.allowed_techniques)

        local restored = restore(serialized, clock)
        assert.are.equal("custom", restored:difficulty())
        assert.are.equal("master", restored.custom_tier)
        assert.are.same({ "swordfish", "x_wing" }, restored.custom_techniques)
        assert.are.equal(0x1234, restored._allowed_techniques)
    end)

    it("rejects invalid custom fields during restore", function()
        local clock = { t = 1000 }
        local instance = assert(game.new({
            puzzle = board.from_string(PUZZLE),
            solution = board.from_string(SOLUTION),
            difficulty = "custom",
            custom_tier = "master",
            custom_techniques = { "swordfish" },
            allowed_techniques = 0x1234,
            now = function()
                return clock.t
            end,
        }))
        local valid_data = instance:serialize()

        -- Custom save with invalid technique for tier
        local bad_tech_data = util.deep_copy(valid_data)
        bad_tech_data.custom_techniques = { "jellyfish" } -- jellyfish is expert, not master
        local bad1, err1 = game.restore(bad_tech_data, {
            now = function()
                return 1000
            end,
        })
        assert.is_nil(bad1)
        assert.is_string(err1)

        -- Custom save missing allowed_techniques
        local bad_no_allowed = util.deep_copy(valid_data)
        bad_no_allowed.allowed_techniques = nil
        local bad2, err2 = game.restore(bad_no_allowed, {
            now = function()
                return 1000
            end,
        })
        assert.is_nil(bad2)
        assert.is_string(err2)

        -- Non-custom save with custom fields
        local bad_non_custom = util.deep_copy(valid_data)
        bad_non_custom.difficulty = "easy"
        local bad3, err3 = game.restore(bad_non_custom, {
            now = function()
                return 1000
            end,
        })
        assert.is_nil(bad3)
        assert.is_string(err3)
    end)
end)
