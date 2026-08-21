-- Benchmark solver performance (nodes/sec and total time across puzzle types).
-- Run with:
--   third_party/koreader/koreader-emulator-arm64-apple-darwin25.5.0-debug/koreader/luajit tools/bench_solver.lua

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local project_root = script_path:match("^(.*)/tools/[^/]+$") or "."
package.path = project_root .. "/sudokuplus.koplugin/?.lua;" .. package.path

local board = require("sudokuplus.core.board")
local solver = require("sudokuplus.core.solver")
local prng = require("sudokuplus.core.prng")

local PUZZLES = {
    unique = "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
    two = "295743861431865900876192543387459216612387495549216738763504189928671354154938600",
    six = "295743001431865900876192543387459216612387495549216738763500000000000000000000000",
    empty = "000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    hard = "000000085000210009960080100500800016000000000890006007009070052300054000480000000",
}

local ITERATIONS = 1000

print(string.format("Running solver benchmark (%d iterations per puzzle)...", ITERATIONS))
print(string.format("%-12s | %-12s | %-12s | %-12s", "Puzzle", "Time (ms)", "Total Nodes", "Nodes/sec"))
print(string.rep("-", 55))

for name, puzzle_str in pairs(PUZZLES) do
    local b = board.from_string(puzzle_str)
    local start_time = os.clock()
    local total_nodes = 0

    for i = 1, ITERATIONS do
        local s = solver.new(b, { rng = prng.new(i), search_budget = 1000000 })
        if name == "empty" then
            s:solve_until(1)
        else
            s:solve_all()
        end
        total_nodes = total_nodes + (s.search_nodes or 0)
    end

    local elapsed_ms = (os.clock() - start_time) * 1000
    local nodes_per_sec = (elapsed_ms > 0) and (total_nodes / (elapsed_ms / 1000)) or 0

    print(string.format("%-12s | %12.2f | %12d | %12.0f", name, elapsed_ms, total_nodes, nodes_per_sec))
end
