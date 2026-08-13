-- Benchmark the hint path (core.hints.next) with the LuaJIT runtime shipped
-- by KOReader. This is the per-request cost a player pays on every hint tap:
-- state validation + a fresh solver + the first-change propagation pass.
-- Run from the project root, for example:
--   third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit tools/bench_hints.lua

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudoku.koplugin/?.lua;" .. package.path

local generator = require("core.generator")
local hints = require("core.hints")
local masks = require("core.masks")
local prng = require("core.prng")

local DEFAULT_SEED = 20260809
local DEFAULT_ITERATIONS = 10
local DIFFICULTIES = { "beginner", "easy", "medium", "hard", "master", "expert" }

local function usage()
    print([[Usage: luajit tools/bench_hints.lua [options]

Options:
  --iterations=N  Hint requests per game (default: 10)
  --seed=N        Starting seed for deterministic games (default: 20260809)
  --quick         One iteration per game
  --help          Show this help

The timer reports CPU time from os.clock(). Run this with KOReader's bundled
LuaJIT, and repeat it on the target reader for meaningful device timings.]])
end

local function fail(message)
    io.stderr:write("bench_hints: " .. message .. "\n")
    os.exit(2)
end

local function parse_integer(value, option, minimum)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or number < minimum then
        fail(option .. " must be an integer >= " .. minimum)
    end
    return number
end

local function parse_options(arguments)
    local options = {
        iterations = DEFAULT_ITERATIONS,
        seed = DEFAULT_SEED,
    }
    for index = 1, #arguments do
        local argument = arguments[index]
        if argument == "--help" then
            usage()
            os.exit(0)
        elseif argument == "--quick" then
            options.iterations = 1
        else
            local option, value = argument:match("^(%-%-[^=]+)=(.+)$")
            if option == "--iterations" then
                options.iterations = parse_integer(value, option, 1)
            elseif option == "--seed" then
                options.seed = parse_integer(value, option, 0)
            else
                fail("unknown option '" .. argument .. "'")
            end
        end
    end
    return options
end

local function new_stats()
    return { samples = 0, durations = {}, statuses = {} }
end

local function percentile(samples, fraction)
    if #samples == 0 then
        return 0
    end
    local sorted = {}
    for index, value in ipairs(samples) do
        sorted[index] = value
    end
    table.sort(sorted)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function maximum(samples)
    local value = 0
    for _, sample in ipairs(samples) do
        value = math.max(value, sample)
    end
    return value
end

local function print_stats(name, stats)
    local statuses = {}
    for status, count in pairs(stats.statuses) do
        statuses[#statuses + 1] = status .. "=" .. count
    end
    table.sort(statuses)
    print(string.format("%s: samples=%d (%s)", name, stats.samples, table.concat(statuses, ", ")))
    print(
        string.format(
            "  hint          p50=%8.3f ms  p95=%8.3f ms  max=%8.3f ms",
            percentile(stats.durations, 0.50),
            percentile(stats.durations, 0.95),
            maximum(stats.durations)
        )
    )
end

local function main(arguments)
    local options = parse_options(arguments)
    local overall = new_stats()

    for difficulty_index, difficulty in ipairs(DIFFICULTIES) do
        local seed = options.seed + difficulty_index * 1000
        local payload, gen_err = generator.generate_game {
            difficulty = difficulty,
            seed = seed,
            rng = prng.new(seed),
        }
        if not payload then
            fail(difficulty .. " generation failed: " .. tostring(gen_err))
        end

        -- Board-legal candidate notes for the empty cells, the state the game
        -- layer derives before each hint request.
        local constraint_masks = masks.new()
        for i = 1, 81 do
            if payload.board[i] ~= 0 then
                masks.add_number(constraint_masks, math.floor((i - 1) / 9), (i - 1) % 9, payload.board[i])
            end
        end
        local notes = {}
        for r = 0, 8 do
            notes[r + 1] = {}
            for c = 0, 8 do
                local mask = 0
                if payload.board[r * 9 + c + 1] == 0 then
                    mask = masks.compute_candidates_mask_for_cell(constraint_masks, r, c)
                end
                notes[r + 1][c + 1] = mask
            end
        end

        local state = {
            board = payload.board,
            notes = notes,
            solution = payload.solution,
            revision = 0,
        }

        local stats = new_stats()
        for _ = 1, options.iterations do
            local started = os.clock()
            local result, err = hints.next(state)
            local elapsed = (os.clock() - started) * 1000
            if not result then
                fail(difficulty .. " hint request failed: " .. tostring(err))
            end
            stats.samples = stats.samples + 1
            stats.durations[#stats.durations + 1] = elapsed
            stats.statuses[result.status] = (stats.statuses[result.status] or 0) + 1
            overall.samples = overall.samples + 1
            overall.durations[#overall.durations + 1] = elapsed
            overall.statuses[result.status] = (overall.statuses[result.status] or 0) + 1
        end
        print_stats(difficulty, stats)
    end

    print_stats("overall", overall)
end

main(arg)
