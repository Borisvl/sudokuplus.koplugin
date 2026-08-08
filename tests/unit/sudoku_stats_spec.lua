package.path = "plugins/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")
local game = require("game")
local stats = require("stats")

local NAKED_SINGLE_PUZZLE = "385421967194756328627983145571892634839645271246137589462579813918364752753218490"
local NAKED_SINGLE_SOLUTION = "385421967194756328627983145571892634839645271246137589462579813918364752753218496"

local function record(overrides)
    local base = {
        kind = "finished",
        difficulty = "easy",
        duration = 60,
        hints = {},
        mistakes = 0,
        check_errors = 0,
        timestamp = 1000,
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

describe("stats", function()
    it("starts empty with a zero streak", function()
        local s = stats.new()
        local summary = stats.summary(s)

        assert.are.equal(0, summary.games_played)
        assert.are.equal(0, summary.finished_count)
        assert.are.equal(0, summary.given_up_count)
        assert.are.equal(0, summary.streak)
        assert.are.equal(0, #s.finished)
        assert.are.equal(0, #s.given_up)
        assert.are.equal(1, s.version)
    end)

    it("accepts finished and give-up records into their own lists", function()
        local s = stats.new()
        assert.is_not_nil(stats.add(s, record()))
        assert.is_not_nil(stats.add(s, record({ kind = "give_up", difficulty = "medium", duration = 30 })))

        assert.are.equal(1, #s.finished)
        assert.are.equal(1, #s.given_up)
        assert.are.equal("easy", s.finished[1].difficulty)
        assert.are.equal(30, s.given_up[1].duration)

        local summary = stats.summary(s)
        assert.are.equal(2, summary.games_played)
        assert.are.equal(1, summary.finished_count)
        assert.are.equal(1, summary.given_up_count)
    end)

    it("accepts records returned by a game that used a hint", function()
        local instance = assert(game.new({
            puzzle = board.from_string(NAKED_SINGLE_PUZZLE),
            solution = board.from_string(NAKED_SINGLE_SOLUTION),
            difficulty = "easy",
            now = function()
                return 1000
            end,
        }))
        assert.are.equal("available", instance:hint().status)

        local result = assert(stats.add(stats.new(), assert(instance:give_up())))
        assert.are.equal(1, #result.given_up)
        assert.are.equal("naked_singles", result.given_up[1].hints[1])
    end)

    it("rejects malformed records", function()
        local s = stats.new()

        local bad_kind, kind_err = stats.add(s, record({ kind = "quitting" }))
        assert.is_nil(bad_kind)
        assert.is_string(kind_err)

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

        local bad_timestamp, timestamp_err = stats.add(s, record({ timestamp = "yesterday" }))
        assert.is_nil(bad_timestamp)
        assert.is_string(timestamp_err)

        assert.are.equal(0, #s.finished)
    end)

    it("computes per-difficulty count, average and best time", function()
        local s = stats.new()
        stats.add(s, record({ difficulty = "easy", duration = 100 }))
        stats.add(s, record({ difficulty = "easy", duration = 300 }))
        stats.add(s, record({ difficulty = "hard", duration = 2000 }))
        stats.add(s, record({ kind = "give_up", difficulty = "easy", duration = 5 }))

        local easy = stats.summary(s).per_difficulty.easy
        assert.are.equal(2, easy.count)
        assert.are.equal(200, easy.avg_duration)
        assert.are.equal(100, easy.best_duration)

        local hard = stats.summary(s).per_difficulty.hard
        assert.are.equal(1, hard.count)
        assert.are.equal(2000, hard.avg_duration)
        assert.are.equal(2000, hard.best_duration)

        assert.is_nil(stats.summary(s).per_difficulty.medium, "give-ups are not time stats")
    end)

    it("aggregates hints per technique and finds the most missed strategy", function()
        local s = stats.new()
        stats.add(s, record({ hints = { "naked_pairs", "skyscraper" } }))
        stats.add(s, record({ hints = { "naked_pairs" } }))
        stats.add(s, record({ hints = {} }))

        local summary = stats.summary(s)
        assert.are.equal(2, summary.hints_per_technique.naked_pairs)
        assert.are.equal(1, summary.hints_per_technique.skyscraper)
        assert.are.same({ technique = "naked_pairs", count = 2 }, summary.most_missed)
    end)

    it("breaks most-missed ties deterministically", function()
        local s = stats.new()
        stats.add(s, record({ hints = { "x_wing" } }))
        stats.add(s, record({ hints = { "skyscraper" } }))

        local summary = stats.summary(s)
        assert.are.equal(1, summary.most_missed.count)
        assert.is_true(summary.most_missed.technique == "skyscraper" or summary.most_missed.technique == "x_wing")
        assert.are.equal("skyscraper", summary.most_missed.technique, "ties resolve to the first sorted technique")
    end)

    it("reports no most-missed strategy without hints", function()
        local s = stats.new()
        stats.add(s, record())
        assert.is_nil(stats.summary(s).most_missed)
    end)

    it("tracks the streak: wins without hints extend, hints or give-ups reset", function()
        local s = stats.new()
        assert.are.equal(0, stats.summary(s).streak)

        stats.add(s, record({ timestamp = 1 }))
        assert.are.equal(1, stats.summary(s).streak)
        stats.add(s, record({ timestamp = 2 }))
        assert.are.equal(2, stats.summary(s).streak)

        stats.add(s, record({ timestamp = 3, hints = { "x_wing" } }))
        assert.are.equal(0, stats.summary(s).streak)

        stats.add(s, record({ timestamp = 4 }))
        assert.are.equal(1, stats.summary(s).streak)

        stats.add(s, record({ kind = "give_up", timestamp = 5 }))
        assert.are.equal(0, stats.summary(s).streak)
    end)

    it("caps the record lists by dropping the oldest entries", function()
        local s = stats.new()
        for i = 1, 250 do
            stats.add(s, record({ timestamp = i, duration = i }))
        end
        assert.are.equal(200, #s.finished)
        assert.are.equal(51, s.finished[1].duration, "oldest dropped")
        assert.are.equal(250, s.finished[200].duration, "newest kept")
        assert.are.equal(200, stats.summary(s).games_played)
    end)

    it("caps record lists restored from persisted data", function()
        local finished = {}
        for i = 1, 201 do
            finished[i] = record({ duration = i, timestamp = i })
        end

        local restored, err = stats.from_table({ version = 1, streak = 0, finished = finished, given_up = {} })

        assert.is_nil(err)
        assert.are.equal(200, #restored.finished)
        assert.are.equal(2, restored.finished[1].duration)
        assert.are.equal(201, restored.finished[200].duration)
    end)

    it("rejects non-finite record values", function()
        local s = stats.new()

        local duration_result, duration_err = stats.add(s, record({ duration = math.huge }))
        assert.is_nil(duration_result)
        assert.is_string(duration_err)

        local timestamp_result, timestamp_err = stats.add(s, record({ timestamp = math.huge }))
        assert.is_nil(timestamp_result)
        assert.is_string(timestamp_err)
    end)

    it("round-trips through to_table and from_table", function()
        local s = stats.new()
        stats.add(s, record({ difficulty = "medium", duration = 120, timestamp = 1 }))
        stats.add(s, record({ kind = "give_up", difficulty = "hard", duration = 99, timestamp = 2 }))
        stats.add(
            s,
            record({
                difficulty = "medium",
                duration = 60,
                hints = { "w_wing" },
                mistakes = 2,
                check_errors = 1,
                timestamp = 3,
            })
        )

        local restored, err = stats.from_table(stats.to_table(s))
        assert.is_nil(err)
        assert.is_not_nil(restored)
        assert.are.equal(0, restored.streak, "last win used a hint")
        assert.are.equal(2, #restored.finished)
        assert.are.equal(1, #restored.given_up)
        assert.are.equal("w_wing", restored.finished[2].hints[1])
        assert.are.equal(2, restored.finished[2].mistakes)

        local a = stats.summary(s)
        local b = stats.summary(restored)
        assert.are.equal(a.games_played, b.games_played)
        assert.are.equal(a.streak, b.streak)
        assert.are.equal(a.per_difficulty.medium.avg_duration, b.per_difficulty.medium.avg_duration)
    end)

    it("rejects malformed persisted tables", function()
        local no_table, table_err = stats.from_table("nope")
        assert.is_nil(no_table)
        assert.is_string(table_err)

        local bad_version, version_err = stats.from_table({ version = 99 })
        assert.is_nil(bad_version)
        assert.is_string(version_err)

        local bad_streak, streak_err = stats.from_table({ version = 1, streak = -1, finished = {}, given_up = {} })
        assert.is_nil(bad_streak)
        assert.is_string(streak_err)

        local bad_records, records_err =
            stats.from_table({ version = 1, streak = 0, finished = { { kind = "x" } }, given_up = {} })
        assert.is_nil(bad_records)
        assert.is_string(records_err)
    end)
end)
