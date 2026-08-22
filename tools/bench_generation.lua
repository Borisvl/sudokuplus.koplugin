-- Focused pre/post optimization benchmark using KOReader's LuaJIT.

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudokuplus.koplugin/?.lua;" .. package.path

local flags = require("sudokuplus.core.techniques.flags")
local generator = require("sudokuplus.core.generator")
local prng = require("sudokuplus.core.prng")
local solver = require("sudokuplus.core.solver")
local util = require("sudokuplus.core.util")

local function tier_ids(tier)
    local ids = {}
    for _, technique in ipairs(flags.TECHNIQUES_BY_TIER[tier]) do
        ids[#ids + 1] = technique.id
    end
    return ids
end

local CASES = {
    { name = "standard_master", options = { difficulty = "master", max_attempts = 100 } },
    {
        name = "custom_master_all_probe",
        options = {
            difficulty = "custom",
            target_tier = "master",
            required_techniques = tier_ids("master"),
            max_attempts = 1,
        },
    },
    {
        name = "custom_x_wing_probe",
        options = {
            difficulty = "custom",
            target_tier = "master",
            required_techniques = { "x_wing" },
            max_attempts = 1,
        },
    },
    {
        name = "custom_x_chain_probe",
        options = {
            difficulty = "custom",
            target_tier = "expert",
            required_techniques = { "x_chain" },
            max_attempts = 1,
        },
    },
    {
        name = "custom_aic_probe",
        options = {
            difficulty = "custom",
            target_tier = "expert",
            required_techniques = { "aic" },
            max_attempts = 1,
        },
    },
}

local function fail(message)
    io.stderr:write("bench_generation: " .. message .. "\n")
    os.exit(2)
end

local function usage()
    print([[Usage: luajit tools/bench_generation.lua [options]

Options:
  --iterations=N  Samples per case (default: 25)
  --seed=N        Deterministic base seed (default: 20260807)
  --case=NAME     Run one focused case
  --quick         Run one sample per case
  --help          Show this help

Custom cases are one-attempt probes so the benchmark isolates uniqueness and
AIC work without spending 100 attempts on every rare target.]])
end

local function positive_integer(value, option)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or number < 1 then
        fail(option .. " must be a positive integer")
    end
    return number
end

local function parse(arguments)
    local options = { iterations = 25, seed = 20260807 }
    for _, argument in ipairs(arguments) do
        if argument == "--help" then
            usage()
            os.exit(0)
        elseif argument == "--quick" then
            options.iterations = 1
        else
            local option, value = argument:match("^(%-%-[^=]+)=(.+)$")
            if option == "--iterations" then
                options.iterations = positive_integer(value, option)
            elseif option == "--seed" then
                options.seed = positive_integer(value, option)
            elseif option == "--case" then
                options.case_name = value
            else
                fail("unknown option '" .. argument .. "'")
            end
        end
    end
    return options
end

local function select_cases(name)
    if not name then
        return CASES
    end
    for _, case in ipairs(CASES) do
        if case.name == name then
            return { case }
        end
    end
    fail("unknown case '" .. name .. "'")
end

local function percentile(samples, fraction)
    local sorted = util.deep_copy(samples)
    table.sort(sorted)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function maximum(samples)
    local result = 0
    for _, sample in ipairs(samples) do
        result = math.max(result, sample)
    end
    return result
end

local function verify_unique(payload)
    local verifier, err = solver.new(payload.board, { techniques = 0 })
    assert(verifier, "independent verification failed: " .. tostring(err))
    assert(
        verifier:count_solutions(2) == 1 and not verifier.search_capped,
        "independent verification did not prove exactly one solution"
    )
end

local function run_case(case, case_index, options)
    local durations = {}
    local successes = 0
    local attempts = 0
    local uniqueness_nodes = 0
    local aic_expansions = 0
    for iteration = 1, options.iterations do
        local seed = options.seed + case_index * 10000 + iteration
        local metrics = generator.new_metrics()
        local generation_options = util.deep_copy(case.options)
        generation_options.seed = seed
        generation_options.rng = prng.new(seed)
        generation_options.metrics = metrics

        local started = os.clock()
        local payload = generator.generate_game(generation_options)
        durations[#durations + 1] = (os.clock() - started) * 1000
        if payload then
            successes = successes + 1
            verify_unique(payload)
        end
        attempts = attempts + metrics.attempts.started
        uniqueness_nodes = uniqueness_nodes + metrics.uniqueness.nodes
        aic_expansions = aic_expansions + metrics.aic.expansions
    end

    print(
        string.format(
            "%s: success=%d/%d p50=%.1fms p95=%.1fms max=%.1fms avg_attempts=%.1f nodes=%d aic_expansions=%d",
            case.name,
            successes,
            options.iterations,
            percentile(durations, 0.50),
            percentile(durations, 0.95),
            maximum(durations),
            attempts / options.iterations,
            uniqueness_nodes,
            aic_expansions
        )
    )
end

local options = parse(arg)
print(string.format("Sudoku generation benchmark (%s, seed=%d)", jit and jit.version or _VERSION, options.seed))
for case_index, case in ipairs(select_cases(options.case_name)) do
    run_case(case, case_index, options)
end
