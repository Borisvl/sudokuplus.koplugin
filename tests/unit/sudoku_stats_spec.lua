package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")
local game = require("game")
local stats = require("stats")

local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
local NAKED_SINGLE_SOLUTION = "385421967194756328627983145571892634839645271246137589462579813918364752753218496"

local PUZZLE = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
local SOLUTION = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

local function record(overrides)
    local base = {
        status = "finished",
        id = nil,
        seed = nil,
        difficulty = "easy",
        duration = 60,
        hints = {},
        mistakes = 0,
        check_errors = 0,
        started_at = 1000,
        ended_at = 1060,
        moves = 10,
        filled = 5,
        correct = 5,
        puzzle = PUZZLE,
        solution = SOLUTION,
        board = PUZZLE,
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

local function in_progress_record(overrides)
    local merged = record()
    merged.status = "in_progress"
    merged.ended_at = nil
    for key, value in pairs(overrides or {}) do
        merged[key] = value
    end
    return merged
end

local function find_by_id(entries, id)
    for _, entry in ipairs(entries) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

describe("stats", function()
    it("starts empty with zeroed aggregates", function()
        local s = stats.new()

        assert.are.equal(2, s.version)
        assert.are.equal(0, s.streak)
        assert.are.equal(0, s.best_streak)
        assert.are.equal(1, s.next_id)
        assert.are.equal(0, #s.games)

        local summary = stats.summary(s)
        assert.are.equal(0, summary.games_started)
        assert.are.equal(0, summary.finished_count)
        assert.are.equal(0, summary.given_up_count)
        assert.are.equal(0, summary.abandoned_count)
        assert.are.equal(0, summary.in_progress_count)
        assert.are.equal(0, summary.completion_rate)
        assert.are.equal(0, summary.win_rate)
        assert.are.equal(0, summary.total_playtime)
        assert.is_nil(summary.avg_duration)
        assert.is_nil(summary.best_duration)
        assert.is_nil(summary.avg_mistakes)
        assert.is_nil(summary.avg_moves)
        assert.are.equal(0, summary.streak)
        assert.are.equal(0, summary.best_streak)
    end)

    it("reserves strictly increasing game ids", function()
        local s = stats.new()
        assert.are.equal(1, stats.reserve_id(s))
        assert.are.equal(2, stats.reserve_id(s))
        assert.are.equal(3, stats.reserve_id(s))
        assert.are.equal(4, s.next_id)
    end)

    it("tracks an in-progress game and updates it by id", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))

        assert.is_not_nil(stats.track(s, in_progress_record({ id = id, difficulty = "medium" })))
        assert.are.equal(1, #s.games)
        assert.are.equal("in_progress", s.games[1].status)
        assert.are.equal(id, s.games[1].id)
        assert.is_nil(s.games[1].ended_at)

        assert.is_not_nil(
            stats.track(s, in_progress_record({ id = id, duration = 999, moves = 20, difficulty = "medium" }))
        )
        assert.are.equal(1, #s.games, "track updates the live entry in place")
        assert.are.equal(999, s.games[1].duration)
        assert.are.equal(20, s.games[1].moves)

        local no_id, no_id_err = stats.track(s, in_progress_record({ id = nil }))
        assert.is_nil(no_id)
        assert.is_string(no_id_err)

        local duplicate, duplicate_err = stats.track(s, record({ id = id }))
        assert.is_nil(duplicate, "tracking a finished game id is rejected")
        assert.is_string(duplicate_err)
    end)

    it("finalizes a tracked game by id on finish", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = id, duration = 30 })))

        assert.is_not_nil(stats.add(s, record({ id = id, duration = 120, ended_at = 2000, correct = 20 })))
        assert.are.equal(1, #s.games, "finalizing updates the live entry, not a new one")
        assert.are.equal("finished", s.games[1].status)
        assert.are.equal(120, s.games[1].duration)
        assert.are.equal(2000, s.games[1].ended_at)
        assert.are.equal(20, s.games[1].correct)
        assert.are.equal(1000, s.games[1].started_at, "the started timestamp survives")
        assert.are.equal(1, stats.summary(s).finished_count)
    end)

    it("appends terminal entries that were never tracked", function()
        local s = stats.new()
        assert.is_not_nil(stats.add(s, record({ id = 1 })))
        assert.are.equal(1, #s.games)
        assert.are.equal("finished", s.games[1].status)

        assert.is_not_nil(stats.add(s, record({ id = 2, status = "give_up" })))
        assert.are.equal(2, #s.games)
        assert.are.equal("give_up", s.games[2].status)
    end)

    it("does not log a give-up without any started move", function()
        local s = stats.new()
        local never = record({ id = 1, status = "give_up", ended_at = 100 })
        never.started_at = nil
        assert.is_not_nil(stats.add(s, never))
        assert.are.equal(0, #s.games, "a never-started give-up leaves no trace")
    end)

    it("marks a tracked game abandoned", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = id, duration = 45 })))

        assert.is_not_nil(stats.abandon(s, id, 2000))
        assert.are.equal("abandoned", s.games[1].status)
        assert.are.equal(2000, s.games[1].ended_at)
        assert.are.equal(1, stats.summary(s).abandoned_count)

        local missing, missing_err = stats.abandon(s, 999, 2000)
        assert.is_nil(missing, "abandoning an untracked id is rejected")
        assert.is_string(missing_err)

        local again, again_err = stats.abandon(s, id, 3000)
        assert.is_nil(again, "abandoning an already-abandoned game is rejected")
        assert.is_string(again_err)
    end)

    it("drops an in-progress game from the log", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = id, duration = 45 })))
        assert.are.equal(1, #s.games)

        assert.is_not_nil(stats.drop_in_progress(s, id))
        assert.are.equal(0, #s.games)

        -- Dropping non-existent or finished id is a safe no-op
        assert.is_not_nil(stats.drop_in_progress(s, 999))
        assert.are.equal(0, #s.games)
    end)

    it("accepts records returned by a real game", function()
        local instance = assert(game.new({
            puzzle = board.from_string(NAKED_SINGLE_PUZZLE),
            solution = board.from_string(NAKED_SINGLE_SOLUTION),
            difficulty = "easy",
            id = 9,
            seed = 55,
            now = function()
                return 1000
            end,
        }))
        local result = assert(instance:hint())
        assert.are.equal("available", result.status)
        assert.is_true(instance:apply_action(result.action))

        local s = assert(stats.add(stats.new(), assert(instance:give_up())))
        assert.are.equal(1, #s.games)
        assert.are.equal("give_up", s.games[1].status)
        assert.are.equal("naked_singles", s.games[1].hints[1])
        assert.are.equal(9, s.games[1].id)
        assert.are.equal(55, s.games[1].seed)
        assert.are.equal(0, s.streak, "a hint-used give-up resets the streak")
    end)

    it("rejects malformed records", function()
        local s = stats.new()

        local bad_status, status_err = stats.add(s, record({ status = "quitting" }))
        assert.is_nil(bad_status)
        assert.is_string(status_err)

        local bad_difficulty, difficulty_err = stats.add(s, record({ difficulty = "impossible" }))
        assert.is_nil(bad_difficulty)
        assert.is_string(difficulty_err)

        local bad_duration, duration_err = stats.add(s, record({ duration = -5 }))
        assert.is_nil(bad_duration)
        assert.is_string(duration_err)

        local bad_hints, hints_err = stats.add(s, record({ hints = "naked_pairs" }))
        assert.is_nil(bad_hints)
        assert.is_string(hints_err)

        local bad_technique, technique_err = stats.add(s, record({ hints = { "not_a_technique" } }))
        assert.is_nil(bad_technique)
        assert.is_string(technique_err)

        local bad_mistakes, mistakes_err = stats.add(s, record({ mistakes = -1 }))
        assert.is_nil(bad_mistakes)
        assert.is_string(mistakes_err)

        local bad_started, started_err = stats.add(s, record({ started_at = "yesterday" }))
        assert.is_nil(bad_started)
        assert.is_string(started_err)

        local bad_board, board_err = stats.add(s, record({ board = "12" }))
        assert.is_nil(bad_board)
        assert.is_string(board_err)

        local bad_id, id_err = stats.add(s, record({ id = 1.5 }))
        assert.is_nil(bad_id)
        assert.is_string(id_err)

        local add_in_progress, add_err = stats.add(s, in_progress_record({ id = 99 }))
        assert.is_nil(add_in_progress)
        assert.is_string(add_err, "add requires a terminal status")

        assert.are.equal(0, #s.games)
    end)

    it("rejects non-finite record values", function()
        local s = stats.new()
        assert.is_nil(stats.add(s, record({ duration = math.huge })))
        assert.is_nil(stats.add(s, record({ started_at = math.huge })))
        assert.is_nil(stats.add(s, record({ ended_at = math.huge })))
    end)

    it("computes per-difficulty count, average, best and mistakes", function()
        local s = stats.new()
        stats.add(s, record({ id = 1, difficulty = "easy", duration = 100, mistakes = 1 }))
        stats.add(s, record({ id = 2, difficulty = "easy", duration = 300, mistakes = 0 }))
        stats.add(s, record({ id = 3, difficulty = "hard", duration = 2000, mistakes = 3 }))
        stats.add(s, record({ id = 4, status = "give_up", difficulty = "easy", duration = 5 }))

        local summary = stats.summary(s)
        local easy = summary.per_difficulty.easy
        assert.are.equal(2, easy.count)
        assert.are.equal(1, easy.given_up_count)
        assert.are.equal(200, easy.avg_duration)
        assert.are.equal(100, easy.best_duration)
        assert.are.equal(0.5, easy.avg_mistakes)

        local hard = summary.per_difficulty.hard
        assert.are.equal(1, hard.count)
        assert.are.equal(2000, hard.avg_duration)
        assert.are.equal(2000, hard.best_duration)
        assert.are.equal(3, hard.avg_mistakes)

        assert.is_nil(summary.per_difficulty.medium, "no games at that difficulty")
    end)

    it("aggregates totals, rates, playtime and mistakes", function()
        local s = stats.new()
        stats.add(s, record({ id = 1, difficulty = "easy", duration = 100, mistakes = 1 }))
        stats.add(s, record({ id = 2, difficulty = "easy", duration = 300 }))
        stats.add(s, record({ id = 3, difficulty = "hard", duration = 2000, mistakes = 3 }))
        stats.add(s, record({ id = 4, status = "give_up", difficulty = "easy", duration = 5, mistakes = 2 }))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = 5, duration = 20 })))
        assert.is_not_nil(stats.abandon(s, 5, 1020))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = 6, duration = 40 })))

        local summary = stats.summary(s)
        assert.are.equal(6, summary.games_started)
        assert.are.equal(3, summary.finished_count)
        assert.are.equal(1, summary.given_up_count)
        assert.are.equal(1, summary.abandoned_count)
        assert.are.equal(1, summary.in_progress_count)
        assert.are.equal(3 / 6, summary.completion_rate)
        assert.are.equal(3 / 4, summary.win_rate)
        assert.are.equal(100 + 300 + 2000 + 5 + 20 + 40, summary.total_playtime)
        assert.are.equal((100 + 300 + 2000) / 3, summary.avg_duration)
        assert.are.equal(100, summary.best_duration)
        assert.are.equal((1 + 0 + 3 + 2) / 4, summary.avg_mistakes, "mistakes average over finished and given-up")
        assert.are.equal(6, summary.total_mistakes)
        assert.are.equal(10, summary.avg_moves, "every record carries 10 moves")
    end)

    it("aggregates hints per technique and finds the most missed strategy", function()
        local s = stats.new()
        stats.add(s, record({ id = 1, hints = { "naked_pairs", "skyscraper" } }))
        stats.add(s, record({ id = 2, hints = { "naked_pairs" } }))
        stats.add(s, record({ id = 3, hints = {} }))

        local summary = stats.summary(s)
        assert.are.equal(2, summary.hints_per_technique.naked_pairs)
        assert.are.equal(1, summary.hints_per_technique.skyscraper)
        assert.are.same({ technique = "naked_pairs", count = 2 }, summary.most_missed)
    end)

    it("counts hints from give-ups and abandons in the missed-strategy summary", function()
        local s = stats.new()
        stats.add(s, record({ id = 1, hints = { "skyscraper" } }))
        stats.add(s, record({ id = 2, status = "give_up", hints = { "skyscraper", "w_wing" } }))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = 3, hints = { "w_wing" } })))
        assert.is_not_nil(stats.abandon(s, 3, 1000))

        local summary = stats.summary(s)
        assert.are.equal(2, summary.hints_per_technique.skyscraper)
        assert.are.equal(2, summary.hints_per_technique.w_wing)
        assert.are.same({ technique = "skyscraper", count = 2 }, summary.most_missed)
    end)

    it("breaks most-missed ties deterministically", function()
        local s = stats.new()
        stats.add(s, record({ id = 1, hints = { "x_wing" } }))
        stats.add(s, record({ id = 2, hints = { "skyscraper" } }))

        local summary = stats.summary(s)
        assert.are.equal(1, summary.most_missed.count)
        assert.is_true(summary.most_missed.technique == "skyscraper" or summary.most_missed.technique == "x_wing")
        assert.are.equal("skyscraper", summary.most_missed.technique, "ties resolve to the first sorted technique")
    end)

    it("reports no most-missed strategy without hints", function()
        local s = stats.new()
        stats.add(s, record({ id = 1 }))
        assert.is_nil(stats.summary(s).most_missed)
    end)

    it("tracks the streak: hint-free wins extend, hints, give-ups and abandons reset", function()
        local s = stats.new()
        assert.are.equal(0, stats.summary(s).streak)

        stats.add(s, record({ id = 1 }))
        assert.are.equal(1, stats.summary(s).streak)
        stats.add(s, record({ id = 2 }))
        assert.are.equal(2, stats.summary(s).streak)
        assert.are.equal(2, stats.summary(s).best_streak)

        stats.add(s, record({ id = 3, hints = { "x_wing" } }))
        assert.are.equal(0, stats.summary(s).streak)
        assert.are.equal(2, stats.summary(s).best_streak, "best streak survives a reset")

        stats.add(s, record({ id = 4 }))
        assert.are.equal(1, stats.summary(s).streak)

        stats.add(s, record({ id = 5, status = "give_up" }))
        assert.are.equal(0, stats.summary(s).streak)

        assert.is_not_nil(stats.track(s, in_progress_record({ id = 6 })))
        assert.is_not_nil(stats.abandon(s, 6, 1000))
        assert.are.equal(0, stats.summary(s).streak, "abandoning resets the streak")
    end)

    it("lists games newest first", function()
        local s = stats.new()
        for i = 1, 5 do
            stats.add(s, record({ id = i }))
        end
        local list = stats.list(s)
        assert.are.equal(5, #list)
        assert.are.equal(5, list[1].id)
        assert.are.equal(1, list[5].id)
    end)

    it("caps the log and never evicts an in-progress entry", function()
        local s = stats.new()
        local live_id = 1
        assert.is_not_nil(stats.track(s, in_progress_record({ id = live_id })))
        for i = 2, 300 do
            assert.is_not_nil(stats.add(s, record({ id = i })))
        end

        assert.are.equal(200, #s.games, "the log is capped at 200")
        assert.is_not_nil(find_by_id(s.games, live_id), "the live game is never evicted")
        assert.is_nil(find_by_id(s.games, 2), "the oldest finished entry is dropped")
        assert.is_not_nil(find_by_id(s.games, 300), "the newest entry is kept")
    end)

    it("migrates v1 stats into the game log", function()
        local v1 = {
            version = 1,
            streak = 2,
            finished = {
                {
                    kind = "finished",
                    difficulty = "easy",
                    duration = 60,
                    hints = {},
                    mistakes = 0,
                    check_errors = 0,
                    timestamp = 100,
                },
                {
                    kind = "finished",
                    difficulty = "easy",
                    duration = 90,
                    hints = { "x_wing" },
                    mistakes = 1,
                    check_errors = 0,
                    timestamp = 200,
                },
            },
            given_up = {
                {
                    kind = "give_up",
                    difficulty = "hard",
                    duration = 30,
                    hints = {},
                    mistakes = 2,
                    check_errors = 1,
                    timestamp = 300,
                },
            },
        }

        local restored, err = stats.from_table(v1)
        assert.is_nil(err)
        assert.is_not_nil(restored)
        assert.are.equal(2, restored.version)
        assert.are.equal(3, #restored.games)
        assert.are.equal("finished", restored.games[1].status)
        assert.are.equal("give_up", restored.games[3].status)
        assert.are.equal(100, restored.games[1].started_at, "v1 timestamp becomes started_at")
        assert.are.equal(100, restored.games[1].ended_at, "v1 timestamp becomes ended_at")
        assert.is_nil(restored.games[1].seed, "v1 entries have no seed")
        assert.are.equal("x_wing", restored.games[2].hints[1])
        -- streak: hint-free win (1) -> hint win (0) -> give_up (0)
        assert.are.equal(0, restored.streak)
        assert.are.equal(1, restored.best_streak)
    end)

    it("caps migrated v1 data to the newest 200 games", function()
        local finished = {}
        for i = 1, 250 do
            finished[i] = {
                kind = "finished",
                difficulty = "easy",
                duration = i,
                hints = {},
                mistakes = 0,
                check_errors = 0,
                timestamp = i,
            }
        end

        local restored, err = stats.from_table({ version = 1, streak = 0, finished = finished, given_up = {} })
        assert.is_nil(err)
        assert.are.equal(200, #restored.games)
        assert.are.equal(51, restored.games[1].duration, "the oldest entries are dropped")
        assert.are.equal(250, restored.games[200].duration, "the newest entries are kept")
    end)

    it("round-trips through to_table and from_table", function()
        local s = stats.new()
        local id = assert(stats.reserve_id(s))
        assert.is_not_nil(stats.track(s, in_progress_record({ id = id, difficulty = "medium" })))
        assert.is_not_nil(
            stats.add(s, record({ id = id, difficulty = "medium", duration = 120, hints = { "w_wing" } }))
        )
        assert.is_not_nil(stats.add(s, record({ id = 2, status = "give_up", difficulty = "hard", duration = 99 })))

        local restored, err = stats.from_table(stats.to_table(s))
        assert.is_nil(err)
        assert.is_not_nil(restored)
        assert.are.equal(2, #restored.games)
        assert.are.equal("finished", restored.games[1].status)
        assert.are.equal("w_wing", restored.games[1].hints[1])
        assert.are.equal("give_up", restored.games[2].status)
        assert.are.equal(2, restored.next_id, "next_id survives the round trip")

        local a = stats.summary(s)
        local b = stats.summary(restored)
        assert.are.equal(a.games_started, b.games_started)
        assert.are.equal(a.streak, b.streak)
        assert.are.equal(a.best_streak, b.best_streak)
        assert.are.equal(a.per_difficulty.medium.avg_duration, b.per_difficulty.medium.avg_duration)
    end)

    it("rejects malformed persisted tables", function()
        local no_table, table_err = stats.from_table("nope")
        assert.is_nil(no_table)
        assert.is_string(table_err)

        local bad_version, version_err = stats.from_table({ version = 99 })
        assert.is_nil(bad_version)
        assert.is_string(version_err)

        local bad_streak, streak_err =
            stats.from_table({ version = 2, streak = -1, best_streak = 0, next_id = 1, games = {} })
        assert.is_nil(bad_streak)
        assert.is_string(streak_err)

        local bad_best, best_err =
            stats.from_table({ version = 2, streak = 3, best_streak = 2, next_id = 1, games = {} })
        assert.is_nil(bad_best)
        assert.is_string(best_err)

        local bad_next, next_err =
            stats.from_table({ version = 2, streak = 0, best_streak = 0, next_id = 0, games = {} })
        assert.is_nil(bad_next)
        assert.is_string(next_err)

        local bad_games, games_err =
            stats.from_table({ version = 2, streak = 0, best_streak = 0, next_id = 1, games = "x" })
        assert.is_nil(bad_games)
        assert.is_string(games_err)

        local bad_entry, entry_err = stats.from_table({
            version = 2,
            streak = 0,
            best_streak = 0,
            next_id = 1,
            games = { { status = "x" } },
        })
        assert.is_nil(bad_entry)
        assert.is_string(entry_err)
    end)

    it("rejects duplicate ids and multiple in-progress entries on load", function()
        local dup, dup_err = stats.from_table({
            version = 2,
            streak = 0,
            best_streak = 0,
            next_id = 3,
            games = { record({ id = 1 }), record({ id = 1 }) },
        })
        assert.is_nil(dup, "duplicate ids must be rejected")
        assert.is_string(dup_err)

        local multiple, multiple_err = stats.from_table({
            version = 2,
            streak = 0,
            best_streak = 0,
            next_id = 3,
            games = { in_progress_record({ id = 1 }), in_progress_record({ id = 2 }) },
        })
        assert.is_nil(multiple, "multiple in-progress games must be rejected")
        assert.is_string(multiple_err)

        -- migrated v1 entries share a nil id: that must stay valid
        local nil_ids, nil_ids_err = stats.from_table({
            version = 2,
            streak = 0,
            best_streak = 0,
            next_id = 1,
            games = { record({ id = nil }), record({ id = nil }) },
        })
        assert.is_not_nil(nil_ids, "nil ids are not duplicates")
        assert.is_nil(nil_ids_err)
    end)

    it("migrates v1 games in chronological order for the streak", function()
        -- A give-up (timestamp 150) that happened between two hint-free wins
        -- must reset the streak mid-sequence, not at the end.
        local v1 = {
            version = 1,
            finished = {
                {
                    kind = "finished",
                    difficulty = "easy",
                    duration = 60,
                    hints = {},
                    mistakes = 0,
                    check_errors = 0,
                    timestamp = 100,
                },
                {
                    kind = "finished",
                    difficulty = "easy",
                    duration = 60,
                    hints = {},
                    mistakes = 0,
                    check_errors = 0,
                    timestamp = 200,
                },
            },
            given_up = {
                {
                    kind = "give_up",
                    difficulty = "easy",
                    duration = 10,
                    hints = {},
                    mistakes = 0,
                    check_errors = 0,
                    timestamp = 150,
                },
            },
        }

        local restored = assert(stats.from_table(v1))
        -- chronologically: win(100), give-up(150), win(200)
        assert.are.equal(100, restored.games[1].ended_at)
        assert.are.equal("give_up", restored.games[2].status)
        assert.are.equal(200, restored.games[3].ended_at)
        assert.are.equal(1, restored.streak, "the streak is computed across the give-up, not at the list boundary")
    end)
end)
