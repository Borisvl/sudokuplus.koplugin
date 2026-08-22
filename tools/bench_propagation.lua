-- Focused logical-propagation and AIC benchmark using KOReader's LuaJIT.

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudokuplus.koplugin/?.lua;" .. package.path

local bit = require("bit")
local board = require("sudokuplus.core.board")
local candidates = require("sudokuplus.core.candidates")
local generator = require("sudokuplus.core.generator")
local masks = require("sudokuplus.core.masks")
local solve_path = require("sudokuplus.core.solve_path")
local solver = require("sudokuplus.core.solver")
local flags = require("sudokuplus.core.techniques.flags")
local aic = require("sudokuplus.core.techniques.aic")
local propagator = require("sudokuplus.core.techniques.propagator")
local util = require("sudokuplus.core.util")

local FIXTURES = {
    master_x_wing = "000000000760003002002640009403900070000004903005000020010560000370090041000000060",
    x_chain = "3.4.2..8...6.......5..7.3.....68..2.....34....6.15.7...1.........9....6...8217..5",
    xy_chain = "3...4.52858.........2..........74....1....35..5.6...4..78.....21..2......39..68..",
    general_aic = "....8.2....5....4..2...5........7......21..971.4....3...........973..52...8.5136.",
}

local function custom_mask(tier, techniques)
    return assert(util.custom_allowed_techniques(tier, techniques))
end

local CASES = {
    { name = "master_x_wing", puzzle = FIXTURES.master_x_wing, techniques = flags.CUMULATIVE_TIER_FLAGS.master },
    { name = "custom_x_chain", puzzle = FIXTURES.x_chain, techniques = custom_mask("expert", { "x_chain" }) },
    { name = "custom_xy_chain", puzzle = FIXTURES.xy_chain, techniques = custom_mask("expert", { "xy_chain" }) },
    { name = "custom_general_aic", puzzle = FIXTURES.general_aic, techniques = custom_mask("expert", { "aic" }) },
}

local function percentile(samples, fraction)
    local sorted = util.deep_copy(samples)
    table.sort(sorted)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function maximum(samples)
    local result = 0
    for _, value in ipairs(samples) do
        result = math.max(result, value)
    end
    return result
end

local function add_metrics(destination, sample_metrics)
    for key, value in pairs(sample_metrics.aic) do
        if key == "max_live_queue" then
            destination[key] = math.max(destination[key], value)
        else
            destination[key] = destination[key] + value
        end
    end
end

local function run_propagation_case(case)
    local metrics = generator.new_metrics()
    local started = os.clock()
    local instance = assert(solver.new(assert(board.from_string(case.puzzle)), {
        techniques = case.techniques,
        metrics = metrics,
    }))
    local path = solve_path.new()
    instance:propagate(path)
    return {
        elapsed_ms = (os.clock() - started) * 1000,
        metrics = metrics,
    }
end

local function dense_propagator(metrics, options)
    local candidate_grid = candidates.new()
    for row = 0, 8 do
        for col = 0, 8 do
            candidates.set(candidate_grid, row, col, 0x1FF)
        end
    end
    if options.bivalue then
        candidates.set(candidate_grid, 0, 0, bit.bor(bit.lshift(1, 0), bit.lshift(1, 1)))
    end
    return propagator.new(board.new(), masks.new(), candidate_grid, aic.flags(), {
        metrics = metrics,
        aic_max_expansions = options.max_expansions,
    })
end

local function run_aic_case(options)
    local metrics = generator.new_metrics()
    local prop = dense_propagator(metrics, options)
    local started = os.clock()
    aic.apply(prop, solve_path.new())
    return {
        elapsed_ms = (os.clock() - started) * 1000,
        metrics = metrics,
    }
end

local function new_result(name)
    return {
        name = name,
        elapsed = {},
        aic = generator.new_metrics().aic,
    }
end

local function record(result, sample)
    result.elapsed[#result.elapsed + 1] = sample.elapsed_ms
    add_metrics(result.aic, sample.metrics)
end

local function benchmark(iterations)
    local results = {}
    for _, case in ipairs(CASES) do
        local result = new_result(case.name)
        for _ = 1, iterations do
            record(result, run_propagation_case(case))
        end
        results[#results + 1] = result
    end

    for _, entry in ipairs({
        { name = "dense_no_elimination", options = { bivalue = false } },
        { name = "expansion_cap", options = { bivalue = true, max_expansions = 0 } },
    }) do
        local result = new_result(entry.name)
        for _ = 1, iterations do
            record(result, run_aic_case(entry.options))
        end
        results[#results + 1] = result
    end
    return results
end

local function format_case(result)
    return {
        name = result.name,
        p50_ms = percentile(result.elapsed, 0.50),
        p95_ms = percentile(result.elapsed, 0.95),
        max_ms = maximum(result.elapsed),
        aic = result.aic,
    }
end

local function emit_human(results)
    print("Sudoku propagation benchmark (" .. tostring(jit and jit.version or _VERSION) .. ")")
    for _, raw in ipairs(results) do
        local result = format_case(raw)
        print(
            string.format(
                "%s: p50=%.2fms p95=%.2fms max=%.2fms expansions=%d caps=%d max_queue=%d",
                result.name,
                result.p50_ms,
                result.p95_ms,
                result.max_ms,
                result.aic.expansions,
                result.aic.caps,
                result.aic.max_live_queue
            )
        )
    end
end

local function fail(message)
    io.stderr:write("bench_propagation: " .. message .. "\n")
    os.exit(2)
end

local iterations = 25
for _, argument in ipairs(arg) do
    if argument == "--quick" then
        iterations = 1
    elseif argument == "--help" then
        print("Usage: luajit tools/bench_propagation.lua [--iterations=N] [--quick]")
        os.exit(0)
    else
        local value = argument:match("^%-%-iterations=(.+)$")
        local number = value and tonumber(value)
        if not number or number % 1 ~= 0 or number < 1 then
            fail("unknown option '" .. argument .. "'")
        end
        iterations = number
    end
end

local results = benchmark(iterations)
emit_human(results)
