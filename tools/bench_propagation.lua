-- Benchmark Sudoku propagation with the LuaJIT runtime shipped by KOReader.
-- Run from the project root, for example:
--   third_party/koreader/base/build/arm64-apple-darwin25.5.0-debug/luajit tools/bench_propagation.lua

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local flags = require("sudokuplus.core.techniques.flags")
local masks = require("sudokuplus.core.masks")
local prng = require("sudokuplus.core.prng")
local propagator = require("sudokuplus.core.techniques.propagator")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")

local DEFAULT_SEED = 20260807
local DEFAULT_ITERATIONS = 3
local DEFAULT_GENERATED = 5
local GENERATED_CLUE_COUNTS = { 17, 25, 35, 45 }
local FULL_MASK = flags.ALL
local SOLVED_BOARD = "841729635769153482532648719423985176687214953195376824214567398376892541958431267"

local TIERS = {
    { name = "beginner", techniques = flags.BEGINNER },
    { name = "easy", techniques = flags.EASY },
    { name = "medium", techniques = bit.bor(flags.EASY, flags.MEDIUM) },
    { name = "hard", techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, flags.HARD)) },
    { name = "master", techniques = bit.bor(flags.EASY, bit.bor(flags.MEDIUM, bit.bor(flags.HARD, flags.MASTER))) },
    { name = "expert", techniques = FULL_MASK },
}

-- These are the technique fixtures already covered by the unit suite. Keeping
-- them here makes the benchmark stable when the test runner or checkout path
-- changes, and gives each tier a common set of reference boards.
local FIXTURES = {
    {
        name = "naked_singles",
        puzzle = "385421967194756328627983145571892634839645271246137589462579813918364752753218490",
    },
    {
        name = "hidden_singles",
        puzzle = "008007000016083000000000051107290000000000000000046307290000000000860140000300700",
    },
    {
        name = "naked_pairs",
        puzzle = "700009030000105006400260009002083951007000000005600000000000003100000060000004010",
    },
    {
        name = "hidden_pairs",
        puzzle = "000032000000000000007600914096000800005008000030040005050200000700000560904010000",
    },
    {
        name = "locked_candidates",
        puzzle = "984000000000500040000000002006097200003002000000000010005060003407051890030009700",
    },
    {
        name = "naked_triples",
        puzzle = "400500370320000004060000000800002030210840000000000090070090100040651000000070000",
    },
    {
        name = "hidden_triples",
        puzzle = "200000400500000006001034080000500040000000000060790000090200600003009001000080037",
    },
    {
        name = "x_wing",
        puzzle = "000000000760003002002640009403900070000004903005000020010560000370090041000000060",
    },
    {
        name = "naked_quads",
        puzzle = "000000060000030047032500000600007005207010908081004000000002000000000001005870000",
    },
    {
        name = "hidden_quads",
        puzzle = "800570290390000000000200000001000508000496000000800000209000001008000070560000082",
    },
    {
        name = "swordfish",
        puzzle = "160540070008001030030800000700050069600902057000000000000030040000000016000164500",
    },
    {
        name = "jellyfish",
        puzzle = "200000003080030050003402100001205400000090000009308600002506900090020070400000001",
    },
    {
        name = "skyscraper",
        puzzle = "000000000001902060000006790902000600370000950005000004140003005709024000000800000",
    },
    {
        name = "w_wing",
        puzzle = "025100000000009030400708900040000800150400000000060004000000008263040000080390106",
    },
    {
        name = "xy_wing",
        puzzle = "000060000000010863003009000904000000300000704570820000000006580690007000000040030",
    },
    {
        name = "xyz_wing",
        puzzle = "069000000000021000000800400001530080007600050000000100000000003902080010000340205",
    },
    {
        name = "aic_x_chain",
        puzzle = "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5",
    },
    {
        name = "aic_xy_chain",
        puzzle = "3...4.52858.........2..........74....1....35..5.6...4..78.....21..2......39..68..",
    },
    {
        name = "aic_discontinuous_nice_loop",
        puzzle = "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136.",
    },
}

local function usage()
    print([[Usage: luajit tools/bench_propagation.lua [options]

Options:
  --iterations=N  Repeat each board N times (default: 3)
  --generated=N   Generate N boards for each clue count (default: 5)
  --seed=N        Seed for deterministic generated boards (default: 20260807)
  --quick         Use one iteration and one generated board per clue count
  --no-profile    Skip the per-technique profile pass
  --verbose       Print every individual sample
  --help          Show this help

The timer reports CPU time from os.clock(). Run this with KOReader's bundled
LuaJIT, and repeat it on the target reader for meaningful device timings.]])
end

local function fail(message)
    io.stderr:write("bench_propagation: " .. message .. "\n")
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
        generated = DEFAULT_GENERATED,
        seed = DEFAULT_SEED,
        profile = true,
        verbose = false,
    }

    for index = 1, #arguments do
        local argument = arguments[index]
        if argument == "--help" then
            usage()
            os.exit(0)
        elseif argument == "--quick" then
            options.iterations = 1
            options.generated = 1
        elseif argument == "--no-profile" then
            options.profile = false
        elseif argument == "--verbose" then
            options.verbose = true
        else
            local option, value = argument:match("^(%-%-[^=]+)=(.+)$")
            if option == "--iterations" then
                options.iterations = parse_integer(value, option, 1)
            elseif option == "--generated" then
                options.generated = parse_integer(value, option, 0)
            elseif option == "--seed" then
                options.seed = parse_integer(value, option, 0)
            else
                fail("unknown option '" .. argument .. "'")
            end
        end
    end

    return options
end

local function generated_board(rng, clue_count)
    local positions = {}
    local cells = {}
    for index = 1, 81 do
        positions[index] = index
        cells[index] = "0"
    end
    rng:shuffle(positions)
    for index = 1, clue_count do
        local position = positions[index]
        cells[position] = SOLVED_BOARD:sub(position, position)
    end
    return table.concat(cells)
end

local function build_corpus(options)
    local corpus = {}
    for _, fixture in ipairs(FIXTURES) do
        corpus[#corpus + 1] = {
            category = "fixture",
            name = fixture.name,
            puzzle = fixture.puzzle,
        }
    end

    local rng = prng.new(options.seed)
    for _, clue_count in ipairs(GENERATED_CLUE_COUNTS) do
        for index = 1, options.generated do
            corpus[#corpus + 1] = {
                category = "generated",
                clues = clue_count,
                name = string.format("generated_%d_%02d", clue_count, index),
                puzzle = generated_board(rng, clue_count),
            }
        end
    end
    return corpus
end

local function validate_corpus(corpus)
    for _, case in ipairs(corpus) do
        local puzzle, board_error = board.from_string(case.puzzle)
        if not puzzle then
            error(case.name .. " is invalid: " .. tostring(board_error))
        end
        local solver_instance, solver_error = solver.new(puzzle)
        if not solver_instance then
            error(case.name .. " is invalid: " .. tostring(solver_error))
        end
    end
end

local function new_stats()
    return {
        samples = 0,
        setup_ms = {},
        propagation_ms = {},
        total_ms = {},
        capped = 0,
        failures = 0,
        steps = 0,
    }
end

local function record(stats, setup_ms, propagation_ms, total_ms, ok, status, steps)
    stats.samples = stats.samples + 1
    stats.setup_ms[#stats.setup_ms + 1] = setup_ms
    stats.propagation_ms[#stats.propagation_ms + 1] = propagation_ms
    stats.total_ms[#stats.total_ms + 1] = total_ms
    if status == "search_capped" then
        stats.capped = stats.capped + 1
    end
    if not ok then
        stats.failures = stats.failures + 1
    end
    stats.steps = stats.steps + steps
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

local function print_metric(name, samples)
    print(
        string.format(
            "  %-12s p50=%8.3f ms  p95=%8.3f ms  max=%8.3f ms",
            name,
            percentile(samples, 0.50),
            percentile(samples, 0.95),
            maximum(samples)
        )
    )
end

local function print_stats(name, stats)
    print(
        string.format(
            "%s: samples=%d capped=%d failures=%d avg_steps=%.1f",
            name,
            stats.samples,
            stats.capped,
            stats.failures,
            stats.samples > 0 and stats.steps / stats.samples or 0
        )
    )
    print_metric("setup", stats.setup_ms)
    print_metric("propagation", stats.propagation_ms)
    print_metric("total", stats.total_ms)
end

local function run_case(case, techniques)
    local started = os.clock()
    local puzzle = assert(board.from_string(case.puzzle))
    local instance = assert(solver.new(puzzle, { techniques = techniques }))
    local setup_ms = (os.clock() - started) * 1000

    local path = solve_path.new()
    local propagation_started = os.clock()
    local ok, status = instance:propagate(path)
    local propagation_ms = (os.clock() - propagation_started) * 1000
    local total_ms = (os.clock() - started) * 1000
    return setup_ms, propagation_ms, total_ms, ok, status, #path.steps
end

local function print_sample(case, tier, iteration, setup_ms, propagation_ms, total_ms, ok, status, steps)
    print(
        string.format(
            "sample case=%s category=%s tier=%s iteration=%d setup=%.3fms propagation=%.3fms "
                .. "total=%.3fms ok=%s status=%s steps=%d",
            case.name,
            case.category,
            tier.name,
            iteration,
            setup_ms,
            propagation_ms,
            total_ms,
            tostring(ok),
            tostring(status),
            steps
        )
    )
end

local function benchmark_tier(corpus, tier, options)
    local all_stats = new_stats()
    local category_stats = {
        fixture = new_stats(),
        generated = new_stats(),
    }

    for _, case in ipairs(corpus) do
        for iteration = 1, options.iterations do
            local setup_ms, propagation_ms, total_ms, ok, status, steps = run_case(case, tier.techniques)
            record(all_stats, setup_ms, propagation_ms, total_ms, ok, status, steps)
            record(category_stats[case.category], setup_ms, propagation_ms, total_ms, ok, status, steps)
            if options.verbose then
                print_sample(case, tier, iteration, setup_ms, propagation_ms, total_ms, ok, status, steps)
            end
        end
    end

    print_stats(tier.name, all_stats)
    print_stats(tier.name .. "/fixtures", category_stats.fixture)
    print_stats(tier.name .. "/generated", category_stats.generated)
end

local function technique_order()
    local probe = propagator.new(board.new(), masks.new(), candidates.new(), 0)
    local method = getmetatable(probe).propagate_constraints
    for index = 1, 20 do
        local name, value = debug.getupvalue(method, index)
        if name == "technique_order" then
            return value
        end
    end
    error("could not inspect propagator technique order")
end

local function profile_case(case, tier)
    local order = technique_order()
    local names = propagator.technique_names()
    local original_apply = {}
    local stats = {}

    for index, technique in ipairs(order) do
        local slot = index
        local original = technique.apply
        original_apply[slot] = original
        technique.apply = function(prop, path)
            local started = os.clock()
            local changed, status = original(prop, path)
            local current = stats[slot]
            if not current then
                current = { calls = 0, changed = 0, elapsed = 0, status = nil }
                stats[slot] = current
            end
            current.calls = current.calls + 1
            current.elapsed = current.elapsed + os.clock() - started
            if changed then
                current.changed = current.changed + 1
            end
            current.status = status or current.status
            return changed, status
        end
    end

    local succeeded, profile_error = pcall(function()
        local instance = assert(solver.new(assert(board.from_string(case.puzzle)), { techniques = tier.techniques }))
        local path = solve_path.new()
        local started = os.clock()
        local ok, status = instance:propagate(path)
        local elapsed = (os.clock() - started) * 1000
        print(
            string.format(
                "profile case=%s tier=%s propagation=%.3fms ok=%s status=%s steps=%d",
                case.name,
                tier.name,
                elapsed,
                tostring(ok),
                tostring(status),
                #path.steps
            )
        )
    end)

    for index, technique in ipairs(order) do
        technique.apply = original_apply[index]
    end
    if not succeeded then
        error(profile_error)
    end

    for index, name in ipairs(names) do
        local stat = stats[index]
        if stat then
            print(
                string.format(
                    "  %-24s calls=%3d changed=%3d time=%8.3fms",
                    name,
                    stat.calls,
                    stat.changed,
                    stat.elapsed * 1000
                )
            )
        else
            print(string.format("  %-24s calls=  0 changed=  0 time=   0.000ms", name))
        end
    end
end

local function find_profile_case(corpus)
    for _, case in ipairs(corpus) do
        if case.category == "generated" and case.clues == 35 then
            return case
        end
    end
    return corpus[1]
end

local function main(arguments)
    local options = parse_options(arguments)
    local corpus = build_corpus(options)
    validate_corpus(corpus)

    print("Sudoku propagation benchmark")
    print("LuaJIT: " .. tostring(jit and jit.version or "unknown"))
    print(
        "seed="
            .. options.seed
            .. " iterations="
            .. options.iterations
            .. " generated_per_clue_count="
            .. options.generated
    )
    print("corpus=" .. #corpus .. " (" .. #FIXTURES .. " fixtures, " .. (#corpus - #FIXTURES) .. " generated)")
    print("")

    for _, tier in ipairs(TIERS) do
        benchmark_tier(corpus, tier, options)
        print("")
    end

    if options.profile then
        print("Per-technique profile (one Expert sample)")
        profile_case(find_profile_case(corpus), TIERS[#TIERS])
    end
end

main(arg)
