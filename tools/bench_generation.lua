-- Benchmark Sudoku puzzle generation with the LuaJIT runtime shipped by KOReader.
-- Run from the project root, for example:
--   third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit tools/bench_generation.lua

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudoku.koplugin/?.lua;" .. package.path

local board = require("core.board")
local generator = require("core.generator")
local prng = require("core.prng")
local solver = require("core.solver")

local DEFAULT_SEED = 20260807
local DEFAULT_ITERATIONS = 3
local DEFAULT_MAX_SECONDS = 3

local CASES = {
    { name = "clues30_none", options = { clues = 30, symmetry = "none" } },
    { name = "clues30_rotational180", options = { clues = 30, symmetry = "rotational180" } },
    { name = "clues30_rotational90", options = { clues = 30, symmetry = "rotational90" } },
    { name = "clues30_mirrorvertical", options = { clues = 30, symmetry = "mirrorvertical" } },
    { name = "clues30_mirrorhorizontal", options = { clues = 30, symmetry = "mirrorhorizontal" } },
    { name = "clues30_mirrordiagonal", options = { clues = 30, symmetry = "mirrordiagonal" } },
    { name = "difficulty_beginner", options = { difficulty = "beginner" } },
    { name = "difficulty_easy", options = { difficulty = "easy" } },
    { name = "difficulty_medium", options = { difficulty = "medium" } },
    -- Keep the hard samples representative without making the default gate
    -- hinge on an unusually unlucky 100-attempt retry sequence.
    { name = "difficulty_hard", seed_offset = 0, options = { difficulty = "hard" } },
    { name = "difficulty_master", options = { difficulty = "master" } },
    { name = "difficulty_expert", options = { difficulty = "expert" } },
}

local function usage()
    print([[Usage: luajit tools/bench_generation.lua [options]

Options:
  --iterations=N   Repeat each generation case N times (default: 3)
  --seed=N         Starting seed for deterministic cases (default: 20260807)
  --max-seconds=N  Fail if any sample exceeds N seconds (default: 3)
  --quick          Run one sample per case
  --help           Show this help

The timer reports CPU time from os.clock(). Run this with KOReader's bundled
LuaJIT, and repeat it on the target reader for meaningful device timings.]])
end

local function fail(message)
    io.stderr:write("bench_generation: " .. message .. "\n")
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
        max_seconds = DEFAULT_MAX_SECONDS,
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
            elseif option == "--max-seconds" then
                options.max_seconds = parse_integer(value, option, 1)
            else
                fail("unknown option '" .. argument .. "'")
            end
        end
    end

    return options
end

local function new_stats()
    return {
        samples = 0,
        successes = 0,
        failures = 0,
        durations = {},
        clues = {},
    }
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

local function clue_range(samples)
    if #samples == 0 then
        return "n/a"
    end

    local minimum = samples[1]
    local maximum_value = samples[1]
    for index = 2, #samples do
        minimum = math.min(minimum, samples[index])
        maximum_value = math.max(maximum_value, samples[index])
    end
    return string.format("%d..%d", minimum, maximum_value)
end

local function record(stats, elapsed, clue_count, succeeded)
    stats.samples = stats.samples + 1
    stats.durations[#stats.durations + 1] = elapsed
    if succeeded then
        stats.successes = stats.successes + 1
        stats.clues[#stats.clues + 1] = clue_count
    else
        stats.failures = stats.failures + 1
    end
end

local function copy_options(case_options, seed)
    local options = {}
    for key, value in pairs(case_options) do
        options[key] = value
    end
    options.rng = prng.new(seed)
    return options
end

local function run_case(case, seed)
    local started = os.clock()
    local puzzle, generation_error = generator.generate(copy_options(case.options, seed))
    local elapsed = os.clock() - started
    if not puzzle then
        return elapsed, 0, false, generation_error
    end

    local valid = solver.validate(puzzle) ~= nil
    local clue_count = board.count_clues(puzzle)
    if not valid or clue_count < 17 or clue_count > 81 then
        return elapsed, clue_count, false, "generated board is invalid"
    end
    return elapsed, clue_count, true
end

local function print_stats(name, stats)
    print(
        string.format(
            "%s: samples=%d successes=%d failures=%d clues=%s",
            name,
            stats.samples,
            stats.successes,
            stats.failures,
            clue_range(stats.clues)
        )
    )
    print(
        string.format(
            "  generation    p50=%8.3f ms  p95=%8.3f ms  max=%8.3f ms",
            percentile(stats.durations, 0.50) * 1000,
            percentile(stats.durations, 0.95) * 1000,
            maximum(stats.durations) * 1000
        )
    )
end

local function main(arguments)
    local options = parse_options(arguments)
    local overall = new_stats()
    local overall_max = 0

    for case_index, case in ipairs(CASES) do
        local stats = new_stats()
        for iteration = 1, options.iterations do
            local seed_offset = case.seed_offset
            if seed_offset == nil then
                seed_offset = case_index * 1000
            end
            local seed = options.seed + seed_offset + iteration
            local elapsed, clue_count, succeeded, generation_error = run_case(case, seed)
            record(stats, elapsed, clue_count, succeeded)
            record(overall, elapsed, clue_count, succeeded)
            overall_max = math.max(overall_max, elapsed)
            if not succeeded then
                print(
                    string.format(
                        "sample case=%s iteration=%d failed after %.3f ms: %s",
                        case.name,
                        iteration,
                        elapsed * 1000,
                        tostring(generation_error)
                    )
                )
            end
        end
        print_stats(case.name, stats)
    end

    print_stats("overall", overall)
    if overall.failures > 0 then
        fail("one or more generation cases failed")
    end
    if overall_max > options.max_seconds then
        fail(string.format("slowest sample took %.3f seconds (limit %.3f)", overall_max, options.max_seconds))
    end
end

main(arg)
